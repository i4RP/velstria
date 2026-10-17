#import "EfkRuntime.h"

#import <Metal/Metal.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#include <Effekseer.h>
#include <EffekseerRendererMetal.h>
#include <algorithm>
#include <atomic>
#include <mutex>
#include <string>
#include <unordered_map>
#pragma clang diagnostic pop

// Effekseer を描く。LLGI のプラットフォーム（ウィンドウ）は使わず、自前（重ね描き）か RealityKit の後処理のレンダーエンコーダを
// Effekseer のコマンドリストへ渡す（EffekseerRendererMetal::BeginRenderPass）。
// 描き手（Renderer）は 2 つで、グラフィックスデバイス（テクスチャ・モデル）を共有する:
//   重ね描き用  BGRA8Unorm・深度なし（CAMetalLayer）
//   後処理用    3D 画面の色の形式・Depth32Float（3D 画面の深度で隠れる）。最初に後処理が形式を知った時に背景で作る
// Manager（効果の状態）は 1 つ。描く直前に Manager の描き手（スプライト・リボン・リング・軌跡・モデル）を経路の描き手へ差し替える。
// スレッド: 再生・移動・進行はメインスレッド、後処理の Draw は描画スレッド。Manager と描き手は _mutex で守る。

namespace {
std::u16string U16(NSString *s) {
    NSData *d = [s dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    return std::u16string(reinterpret_cast<const char16_t *>(d.bytes), d.length / 2);
}
Effekseer::Matrix44 ToEfk(simd_float4x4 m) {
    // simd は列優先・列ベクトル、Effekseer は行優先・行ベクトル。転置同士なので並びはそのまま同じ。
    Effekseer::Matrix44 r;
    memcpy(&r.Values[0][0], &m, sizeof(float) * 16);
    return r;
}
/// 1 つの描き手と、Manager へ差す部品。
struct Painter {
    EffekseerRenderer::RendererRef renderer;
    Effekseer::RefPtr<EffekseerRenderer::SingleFrameMemoryPool> pool;
    Effekseer::RefPtr<EffekseerRenderer::CommandList> commandList;
    Effekseer::SpriteRendererRef sprite;
    Effekseer::RibbonRendererRef ribbon;
    Effekseer::RingRendererRef ring;
    Effekseer::TrackRendererRef track;
    Effekseer::ModelRendererRef model;

    bool make(Effekseer::Backend::GraphicsDeviceRef device, MTLPixelFormat color, MTLPixelFormat depth, bool reversed) {
        renderer = EffekseerRendererMetal::Create(device, 4000, color, depth, reversed);
        if (renderer == nullptr) return false;
        pool = EffekseerRenderer::CreateSingleFrameMemoryPool(renderer->GetGraphicsDevice());
        commandList = EffekseerRenderer::CreateCommandList(renderer->GetGraphicsDevice(), pool);
        sprite = renderer->CreateSpriteRenderer();
        ribbon = renderer->CreateRibbonRenderer();
        ring = renderer->CreateRingRenderer();
        track = renderer->CreateTrackRenderer();
        model = renderer->CreateModelRenderer();
        return pool != nullptr && commandList != nullptr;
    }

    void bind(Effekseer::ManagerRef &m) const {
        m->SetSpriteRenderer(sprite);
        m->SetRibbonRenderer(ribbon);
        m->SetRingRenderer(ring);
        m->SetTrackRenderer(track);
        m->SetModelRenderer(model);
    }

    void reset() {
        model.Reset();
        track.Reset();
        ring.Reset();
        ribbon.Reset();
        sprite.Reset();
        commandList.Reset();
        pool.Reset();
        renderer.Reset();
    }
};
/// 効果の層（Manager のレイヤー）: 0 = 3D に隠れる、1 = 3D の上（後処理の中では深度を遠くに戻してから描く）。
constexpr int32_t LayerOccluded = 0;
constexpr int32_t LayerOnTop = 1;
constexpr int32_t MaskAll = (1 << LayerOccluded) | (1 << LayerOnTop);
/// 安全装置の確かめ専用の層（試合の描画の mask には入れない）。
constexpr int32_t LayerProbe = 2;

/// 錠の中で、今の Manager の状態のうち mask の層を描き手 p で encoder へ描く。newFrame = そのフレームの最初の描画（1 フレーム 1 回）。
void DrawPass(Effekseer::ManagerRef &manager, Painter &p, id<MTLRenderCommandEncoder> enc, simd_float4x4 cameraWorld,
              const Effekseer::Matrix44 &proj, float time, int32_t mask, bool newFrame) {
    if (newFrame) p.pool->NewFrame();
    EffekseerRendererMetal::BeginCommandList(p.commandList);
    p.renderer->SetCommandList(p.commandList);
    EffekseerRendererMetal::BeginRenderPass(p.commandList, enc);
    p.renderer->SetProjectionMatrix(proj);
    p.renderer->SetCameraMatrix(ToEfk(simd_inverse(cameraWorld)));
    p.renderer->SetTime(time);
    p.renderer->BeginRendering();
    Effekseer::Manager::DrawParameter draw;
    draw.ZNear = 0.0f;
    draw.ZFar = 1.0f;
    draw.ViewProjectionMatrix = p.renderer->GetCameraProjectionMatrix();
    draw.CameraCullingMask = mask;
    manager->Draw(draw);
    p.renderer->EndRendering();
    EffekseerRendererMetal::EndRenderPass(p.commandList);
    p.renderer->SetCommandList(nullptr);
    EffekseerRendererMetal::EndCommandList(p.commandList);
}
enum PostState : int { PostNone = 0, PostCreating = 1, PostReady = 2, PostFailed = 3 };
constexpr int BackgroundSlots = 3;
} // namespace

@implementation EfkRuntime {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    CAMetalLayer *_layer;
    Effekseer::ManagerRef _manager;
    Effekseer::Backend::GraphicsDeviceRef _graphics;
    Painter _overlay;
    Painter _post;
    /// Manager に差している描き手（0 = なし、1 = 重ね描き、2 = 後処理）。
    int _bound;
    std::atomic<int> _postState;
    std::atomic<unsigned long> _postFormat;
    std::atomic<bool> _postReversed;
    std::atomic<bool> _inPost;
    std::atomic<NSInteger> _instances;
    /// 後処理の中で描くときのカメラ（advance で覚える）と時刻。
    simd_float4x4 _postCamera;
    std::unordered_map<std::string, Effekseer::EffectRef> _effects;
    double _time;
    dispatch_semaphore_t _inflight;
    BOOL _drewLastFrame;
    std::mutex _mutex;
    /// 歪みの背景（RealityKit が使い回す数枚の 3D 画面）の包み。テクスチャごとに 1 回だけ作る。
    id<MTLTexture> _bgTexture[BackgroundSlots];
    Effekseer::Backend::TextureRef _bgRef[BackgroundSlots];
    int _bgNext;
}

- (nullable instancetype)init {
    self = [super init];
    if (!self) return nil;
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) return nil;
    _queue = [_device newCommandQueue];
    _layer = [CAMetalLayer layer];
    _layer.device = _device;
    _layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _layer.framebufferOnly = YES;
    _layer.opaque = NO;
    _layer.maximumDrawableCount = 3;
    _layer.presentsWithTransaction = NO;
    _inflight = dispatch_semaphore_create(3);
    _postState = PostNone;
    _postFormat = 0;
    _postReversed = false;
    _inPost = false;
    _instances = 0;
    _postCamera = matrix_identity_float4x4;

    _manager = Effekseer::Manager::Create(4000);
    _manager->SetCoordinateSystem(Effekseer::CoordinateSystem::RH);
    _graphics = EffekseerRendererMetal::CreateDevice();
    if (_graphics == nullptr) return nil;
    if (!_overlay.make(_graphics, MTLPixelFormatBGRA8Unorm, MTLPixelFormatInvalid, false)) return nil;
    _overlay.bind(_manager);
    _bound = 1;
    _manager->SetTextureLoader(_overlay.renderer->CreateTextureLoader());
    _manager->SetModelLoader(_overlay.renderer->CreateModelLoader());
    _manager->SetMaterialLoader(_overlay.renderer->CreateMaterialLoader());
    _manager->SetCurveLoader(Effekseer::MakeRefPtr<Effekseer::CurveLoader>());
    return self;
}

- (void)dealloc {
    // 描画中のコマンドバッファが終わってから資源（テクスチャ・バッファ）を解放する（同じキューは直列に実行される）。
    // 後処理のコマンドバッファは RealityKit のキューなので、後処理の描き手が残っていれば少し待つ（解放は試合の後だけ）
    if (_queue != nil) {
        id<MTLCommandBuffer> fence = [_queue commandBuffer];
        [fence commit];
        [fence waitUntilCompleted];
    }
    std::lock_guard<std::mutex> g(_mutex);
    if (_manager != nullptr) _manager->StopAllEffects();
    _effects.clear();
    for (int i = 0; i < BackgroundSlots; i++) {
        _bgRef[i].Reset();
        _bgTexture[i] = nil;
    }
    _post.reset();
    _overlay.reset();
    _graphics.Reset();
    _manager.Reset();
}

- (CAMetalLayer *)layer { return _layer; }
- (NSInteger)loadedCount {
    std::lock_guard<std::mutex> g(_mutex);
    return (NSInteger)_effects.size();
}
- (NSInteger)activeCount { return _instances.load(); }

- (BOOL)loadEffectNamed:(NSString *)name path:(NSString *)path magnification:(float)magnification {
    std::lock_guard<std::mutex> g(_mutex);
    auto effect = Effekseer::Effect::Create(_manager, U16(path).c_str(), magnification);
    if (effect == nullptr) return NO;
    _effects[std::string(name.UTF8String)] = effect;
    return YES;
}

- (BOOL)hasEffectNamed:(NSString *)name {
    std::lock_guard<std::mutex> g(_mutex);
    return _effects.find(std::string(name.UTF8String)) != _effects.end();
}

- (EfkHandle)playNamed:(NSString *)name position:(simd_float3)p yaw:(float)yaw scale:(float)scale speed:(float)speed {
    std::lock_guard<std::mutex> g(_mutex);
    auto it = _effects.find(std::string(name.UTF8String));
    if (it == _effects.end()) return -1;
    Effekseer::Handle h = _manager->Play(it->second, p.x, p.y, p.z);
    if (h < 0) return -1;
    _manager->SetRotation(h, 0, yaw, 0);
    _manager->SetScale(h, scale, scale, scale);
    _manager->SetSpeed(h, speed);
    _instances = (NSInteger)_manager->GetTotalInstanceCount();
    return h;
}

- (void)setPosition:(simd_float3)p yaw:(float)yaw forHandle:(EfkHandle)handle {
    std::lock_guard<std::mutex> g(_mutex);
    _manager->SetLocation(handle, p.x, p.y, p.z);
    _manager->SetRotation(handle, 0, yaw, 0);
}

- (void)setLocation:(simd_float3)p forHandle:(EfkHandle)handle {
    std::lock_guard<std::mutex> g(_mutex);
    _manager->SetLocation(handle, p.x, p.y, p.z);
}

- (void)stopHandle:(EfkHandle)handle {
    std::lock_guard<std::mutex> g(_mutex);
    _manager->StopEffect(handle);
}

- (void)stopAll {
    std::lock_guard<std::mutex> g(_mutex);
    _manager->StopAllEffects();
}

- (void)setOnTop:(BOOL)onTop forHandle:(EfkHandle)handle {
    std::lock_guard<std::mutex> g(_mutex);
    _manager->SetLayer(handle, onTop ? LayerOnTop : LayerOccluded);
}

- (BOOL)isPlayingHandle:(EfkHandle)handle {
    std::lock_guard<std::mutex> g(_mutex);
    return _manager->Exists(handle);
}

// MARK: 進行（錠の中で呼ぶ）

- (void)advanceLocked:(simd_float4x4)cameraWorld dt:(double)dt {
    simd_float3 eye = cameraWorld.columns[3].xyz;
    Effekseer::Manager::LayerParameter layer;
    layer.ViewerPosition = Effekseer::Vector3D(eye.x, eye.y, eye.z);
    _manager->SetLayerParameter(LayerOccluded, layer);
    _manager->SetLayerParameter(LayerOnTop, layer);
    Effekseer::Manager::UpdateParameter update;
    update.DeltaFrame = (float)(dt * 60.0);
    update.UpdateInterval = 1.0f;
    _manager->Update(update);
    _time += dt;
    _instances = (NSInteger)_manager->GetTotalInstanceCount();
}

- (void)bindLocked:(int)which {
    if (_bound == which) return;
    (which == 2 ? _post : _overlay).bind(_manager);
    _bound = which;
}

// MARK: 重ね描き

- (void)renderWithCameraWorld:(simd_float4x4)cameraWorld
                  verticalFOV:(float)fov
                         near:(float)zNear
                          far:(float)zFar
                 deltaSeconds:(double)dt
                 drawableSize:(CGSize)size {
    if (size.width < 1 || size.height < 1) return;
    if (!CGSizeEqualToSize(_layer.drawableSize, size)) _layer.drawableSize = size;

    std::lock_guard<std::mutex> g(_mutex);
    [self advanceLocked:cameraWorld dt:dt];

    // 何も出ていない間は描かない（全画面のクリアを毎フレーム出すと GPU の無駄）。最後の効果が消えた直後の 1 回だけ空の画を出して消す
    BOOL anything = _manager->GetTotalInstanceCount() > 0;
    if (!anything && !_drewLastFrame) return;
    _drewLastFrame = anything;

    // ドローアブルが取れない時（バックグラウンド等）は描かずに進行だけ
    if (dispatch_semaphore_wait(_inflight, DISPATCH_TIME_NOW) != 0) return;
    id<CAMetalDrawable> drawable = [_layer nextDrawable];
    if (!drawable) { dispatch_semaphore_signal(_inflight); return; }

    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    __block dispatch_semaphore_t sem = _inflight;
    [cb addCompletedHandler:^(id<MTLCommandBuffer>) { dispatch_semaphore_signal(sem); }];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:pass];

    [self bindLocked:1];
    float aspect = (float)(size.width / size.height);
    Effekseer::Matrix44 proj;
    proj.PerspectiveFovRH(fov, aspect, zNear, zFar);
    DrawPass(_manager, _overlay, enc, cameraWorld, proj, (float)_time, MaskAll, true);

    [enc endEncoding];
    [cb presentDrawable:drawable];
    [cb commit];
}

/// 重ねのレイヤーに空の画を出す（後処理へ切り替える時。前の効果の画を残さない）。
- (void)presentClearOverlay {
    if (_layer.drawableSize.width < 1 || _layer.drawableSize.height < 1) return;
    if (dispatch_semaphore_wait(_inflight, DISPATCH_TIME_NOW) != 0) return;
    id<CAMetalDrawable> drawable = [_layer nextDrawable];
    if (!drawable) { dispatch_semaphore_signal(_inflight); return; }
    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    __block dispatch_semaphore_t sem = _inflight;
    [cb addCompletedHandler:^(id<MTLCommandBuffer>) { dispatch_semaphore_signal(sem); }];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    [[cb renderCommandEncoderWithDescriptor:pass] endEncoding];
    [cb presentDrawable:drawable];
    [cb commit];
    _drewLastFrame = NO;
}

// MARK: 後処理の中で描く

- (BOOL)drawsInPostProcess { return _inPost.load(); }

- (void)setDrawsInPostProcess:(BOOL)value {
    bool old = _inPost.exchange(value);
    if (old == (bool)value) return;
    // 重ねのレイヤーはメインスレッドで触る（呼び出し側はメインスレッド）
    if (value) {
        [self presentClearOverlay];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _layer.hidden = value;
    [CATransaction commit];
}

- (void)advanceWithCameraWorld:(simd_float4x4)cameraWorld deltaSeconds:(double)dt {
    std::lock_guard<std::mutex> g(_mutex);
    [self advanceLocked:cameraWorld dt:dt];
    _postCamera = cameraWorld;
}

- (BOOL)isPreparedForPostColorFormat:(MTLPixelFormat)format reversedDepth:(BOOL)reversed {
    int state = _postState.load();
    bool same = _postFormat.load() == (unsigned long)format && _postReversed.load() == (bool)reversed;
    if (state == PostReady && same) return YES;
    if (state == PostCreating || (state == PostFailed && same)) return NO;
    // 形式が変わった・まだ無い: 背景で作る（描画スレッドを止めない。作る間はメインスレッドの再生・進行が錠で待つ）
    int expected = state;
    if (!_postState.compare_exchange_strong(expected, PostCreating)) return NO;
    _postFormat = (unsigned long)format;
    _postReversed = reversed;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        std::lock_guard<std::mutex> g(self->_mutex);
        if (self->_bound == 2) {
            self->_overlay.bind(self->_manager);
            self->_bound = 1;
        }
        self->_post.reset();
        bool ok = self->_post.make(self->_graphics, format, MTLPixelFormatDepth32Float, reversed);
        if (ok) {
            // 3D 画面が線形（sRGB・浮動小数）の時は、効果の色（ガンマのまま作った）をガンマのまま保つ
            BOOL linear = format == MTLPixelFormatBGRA8Unorm_sRGB || format == MTLPixelFormatRGBA8Unorm_sRGB ||
                          format == MTLPixelFormatRGBA16Float || format == MTLPixelFormatRG11B10Float ||
                          format == MTLPixelFormatRGBA32Float;
            self->_post.renderer->SetMaintainGammaColorInLinearColorSpace(linear);
        } else {
            self->_post.reset();
        }
        self->_postState = ok ? PostReady : PostFailed;
    });
    return NO;
}

- (BOOL)encodePostWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                   projection:(simd_float4x4)projection
                   background:(nullable id<MTLTexture>)background
                   resetDepth:(void (^_Nullable)(id<MTLRenderCommandEncoder>))resetDepth {
    if (!_inPost.load() || _postState.load() != PostReady) return NO;
    std::lock_guard<std::mutex> g(_mutex);
    if (_post.renderer == nullptr) return NO;
    if (_manager->GetTotalInstanceCount() == 0) return NO;
    [self bindLocked:2];
    if (background != nil) {
        // 歪みの背景（RealityKit が使い回す数枚の 3D 画面）の包みはテクスチャごとに 1 回だけ作る
        int k = -1;
        for (int i = 0; i < BackgroundSlots; i++) {
            if (_bgTexture[i] == background) k = i;
        }
        if (k < 0) {
            k = _bgNext;
            _bgNext = (_bgNext + 1) % BackgroundSlots;
            _bgTexture[k] = background;
            _bgRef[k] = EffekseerRendererMetal::CreateTexture(_graphics, background);
        }
        if (_bgRef[k] != nullptr) _post.renderer->SetBackground(_bgRef[k]);
    }
    // 3D に隠れる層 → 深度を遠くへ戻す → 3D の上の層（旧来の .efk・命中の閃きなど）
    Effekseer::Matrix44 proj = ToEfk(projection);
    DrawPass(_manager, _post, encoder, _postCamera, proj, (float)_time, 1 << LayerOccluded, true);
    if (resetDepth != nil) {
        resetDepth(encoder);
        DrawPass(_manager, _post, encoder, _postCamera, proj, (float)_time, 1 << LayerOnTop, false);
    }
    return YES;
}

- (NSInteger)probePostWithEffectNamed:(NSString *)name
                          colorFormat:(MTLPixelFormat)format
                        reversedDepth:(BOOL)reversed {
    if (_postState.load() != PostReady || _postFormat.load() != (unsigned long)format || _postReversed.load() != (bool)reversed) {
        return -1;
    }
    NSUInteger px = 0;
    if (format == MTLPixelFormatBGRA8Unorm || format == MTLPixelFormatRGBA8Unorm) px = 4;
    else if (format == MTLPixelFormatRGBA16Float) px = 8;
    if (px == 0) return -1;
    std::lock_guard<std::mutex> g(_mutex);
    auto it = _effects.find(std::string(name.UTF8String));
    if (it == _effects.end() || _post.renderer == nullptr) return -1;
    const NSUInteger size = 64;
    MTLTextureDescriptor *cd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:size height:size mipmapped:NO];
    cd.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    cd.storageMode = MTLStorageModePrivate;
    MTLTextureDescriptor *dd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                  width:size height:size mipmapped:NO];
    dd.usage = MTLTextureUsageRenderTarget;
    dd.storageMode = MTLStorageModePrivate;
    id<MTLTexture> color = [_device newTextureWithDescriptor:cd];
    id<MTLTexture> depth = [_device newTextureWithDescriptor:dd];
    id<MTLBuffer> buf = [_device newBufferWithLength:size * size * px options:MTLResourceStorageModeShared];
    if (color == nil || depth == nil || buf == nil) return -1;
    Effekseer::Handle h = _manager->Play(it->second, 0, 0, 0);
    if (h < 0) return -1;
    _manager->SetLayer(h, LayerProbe);
    // この効果だけを 4 フレーム進め、描く組へ移す（Draw は前の Flip の組を描く。ほかの効果は進めない）
    _manager->BeginUpdate();
    _manager->UpdateHandle(h, 4.0f);
    _manager->EndUpdate();
    _manager->Flip();

    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = color;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.depthAttachment.texture = depth;
    pass.depthAttachment.loadAction = MTLLoadActionClear;
    pass.depthAttachment.clearDepth = reversed ? 0.0 : 1.0;
    pass.depthAttachment.storeAction = MTLStoreActionDontCare;
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:pass];
    [self bindLocked:2];
    // カメラは原点の 4 m 手前（+Z）から -Z を向く。射影は深度の向きに合わせる（画角 60°）
    simd_float4x4 cam = matrix_identity_float4x4;
    cam.columns[3] = simd_make_float4(0, 0, 4, 1);
    float f = 1.0f / tanf(30.0f * (float)M_PI / 180.0f), n = 0.5f, fz = 100.0f;
    simd_float4x4 proj = reversed
        ? simd_matrix(simd_make_float4(f, 0, 0, 0), simd_make_float4(0, f, 0, 0), simd_make_float4(0, 0, 0, -1),
                      simd_make_float4(0, 0, n, 0))
        : simd_matrix(simd_make_float4(f, 0, 0, 0), simd_make_float4(0, f, 0, 0), simd_make_float4(0, 0, fz / (n - fz), -1),
                      simd_make_float4(0, 0, n * fz / (n - fz), 0));
    DrawPass(_manager, _post, enc, cam, ToEfk(proj), (float)_time, 1 << LayerProbe, true);
    [enc endEncoding];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit copyFromTexture:color sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
               sourceSize:MTLSizeMake(size, size, 1) toBuffer:buf destinationOffset:0
      destinationBytesPerRow:size * px destinationBytesPerImage:size * size * px];
    [blit endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    _manager->StopEffect(h);
    if (cb.status != MTLCommandBufferStatusCompleted) return -1;
    NSInteger lit = 0;
    if (px == 4) {
        const uint8_t *p = (const uint8_t *)buf.contents;
        for (NSUInteger i = 0; i < size * size; i++) {
            if (std::max(p[i * 4], std::max(p[i * 4 + 1], p[i * 4 + 2])) > 10) lit++;
        }
    } else {
        const __fp16 *p = (const __fp16 *)buf.contents;
        for (NSUInteger i = 0; i < size * size; i++) {
            float m = std::max((float)p[i * 4], std::max((float)p[i * 4 + 1], (float)p[i * 4 + 2]));
            if (m > 0.04f) lit++;
        }
    }
    return lit;
}

- (BOOL)debugEncodeOverlayWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                          cameraWorld:(simd_float4x4)cameraWorld
                           projection:(simd_float4x4)projection {
    std::lock_guard<std::mutex> g(_mutex);
    if (_manager->GetTotalInstanceCount() == 0) return NO;
    [self bindLocked:1];
    DrawPass(_manager, _overlay, encoder, cameraWorld, ToEfk(projection), (float)_time, MaskAll, true);
    return YES;
}

+ (BOOL)isReversedDepthProjection:(simd_float4x4)p {
    // 視線の前（-Z）の近い点と遠い点の深度（z / w）を比べる
    simd_float4 nearP = simd_mul(p, simd_make_float4(0, 0, -1, 1));
    simd_float4 farP = simd_mul(p, simd_make_float4(0, 0, -100, 1));
    if (fabsf(nearP.w) < 1e-6f || fabsf(farP.w) < 1e-6f) return NO;
    return nearP.z / nearP.w > farP.z / farP.w;
}

@end
