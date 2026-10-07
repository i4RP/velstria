#import "EfkRuntime.h"

#import <Metal/Metal.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#include <Effekseer.h>
#include <EffekseerRendererMetal.h>
#include <string>
#include <unordered_map>
#pragma clang diagnostic pop

// Effekseer を 1 つの Metal レイヤーへ描く。LLGI のプラットフォーム（ウィンドウ）は使わず、自前のコマンドバッファ・
// レンダーエンコーダを Effekseer のコマンドリストへ渡す（EffekseerRendererMetal::BeginRenderPass）。

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
} // namespace

@implementation EfkRuntime {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    CAMetalLayer *_layer;
    Effekseer::ManagerRef _manager;
    EffekseerRenderer::RendererRef _renderer;
    Effekseer::RefPtr<EffekseerRenderer::SingleFrameMemoryPool> _pool;
    Effekseer::RefPtr<EffekseerRenderer::CommandList> _commandList;
    std::unordered_map<std::string, Effekseer::EffectRef> _effects;
    double _time;
    dispatch_semaphore_t _inflight;
    BOOL _drewLastFrame;
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

    _manager = Effekseer::Manager::Create(4000);
    _manager->SetCoordinateSystem(Effekseer::CoordinateSystem::RH);
    _renderer = EffekseerRendererMetal::Create(4000, MTLPixelFormatBGRA8Unorm, MTLPixelFormatInvalid, false);
    if (_renderer == nullptr) return nil;
    _pool = EffekseerRenderer::CreateSingleFrameMemoryPool(_renderer->GetGraphicsDevice());
    _commandList = EffekseerRenderer::CreateCommandList(_renderer->GetGraphicsDevice(), _pool);

    _manager->SetSpriteRenderer(_renderer->CreateSpriteRenderer());
    _manager->SetRibbonRenderer(_renderer->CreateRibbonRenderer());
    _manager->SetRingRenderer(_renderer->CreateRingRenderer());
    _manager->SetTrackRenderer(_renderer->CreateTrackRenderer());
    _manager->SetModelRenderer(_renderer->CreateModelRenderer());
    _manager->SetTextureLoader(_renderer->CreateTextureLoader());
    _manager->SetModelLoader(_renderer->CreateModelLoader());
    _manager->SetMaterialLoader(_renderer->CreateMaterialLoader());
    _manager->SetCurveLoader(Effekseer::MakeRefPtr<Effekseer::CurveLoader>());
    return self;
}

- (void)dealloc {
    // 描画中のコマンドバッファが終わってから資源（テクスチャ・バッファ）を解放する（同じキューは直列に実行される）
    if (_queue != nil) {
        id<MTLCommandBuffer> fence = [_queue commandBuffer];
        [fence commit];
        [fence waitUntilCompleted];
    }
    if (_manager != nullptr) _manager->StopAllEffects();
    _effects.clear();
    _commandList.Reset();
    _pool.Reset();
    _renderer.Reset();
    _manager.Reset();
}

- (CAMetalLayer *)layer { return _layer; }
- (NSInteger)loadedCount { return (NSInteger)_effects.size(); }
- (NSInteger)activeCount { return _manager != nullptr ? (NSInteger)_manager->GetTotalInstanceCount() : 0; }

- (BOOL)loadEffectNamed:(NSString *)name path:(NSString *)path magnification:(float)magnification {
    auto effect = Effekseer::Effect::Create(_manager, U16(path).c_str(), magnification);
    if (effect == nullptr) return NO;
    _effects[std::string(name.UTF8String)] = effect;
    return YES;
}

- (BOOL)hasEffectNamed:(NSString *)name {
    return _effects.find(std::string(name.UTF8String)) != _effects.end();
}

- (EfkHandle)playNamed:(NSString *)name position:(simd_float3)p yaw:(float)yaw scale:(float)scale speed:(float)speed {
    auto it = _effects.find(std::string(name.UTF8String));
    if (it == _effects.end()) return -1;
    Effekseer::Handle h = _manager->Play(it->second, p.x, p.y, p.z);
    if (h < 0) return -1;
    _manager->SetRotation(h, 0, yaw, 0);
    _manager->SetScale(h, scale, scale, scale);
    _manager->SetSpeed(h, speed);
    return h;
}

- (void)setPosition:(simd_float3)p yaw:(float)yaw forHandle:(EfkHandle)handle {
    _manager->SetLocation(handle, p.x, p.y, p.z);
    _manager->SetRotation(handle, 0, yaw, 0);
}

- (void)setLocation:(simd_float3)p forHandle:(EfkHandle)handle { _manager->SetLocation(handle, p.x, p.y, p.z); }
- (void)stopHandle:(EfkHandle)handle { _manager->StopEffect(handle); }
- (void)stopAll { _manager->StopAllEffects(); }
- (BOOL)isPlayingHandle:(EfkHandle)handle { return _manager->Exists(handle); }

- (void)renderWithCameraWorld:(simd_float4x4)cameraWorld
                  verticalFOV:(float)fov
                         near:(float)zNear
                          far:(float)zFar
                 deltaSeconds:(double)dt
                 drawableSize:(CGSize)size {
    if (size.width < 1 || size.height < 1) return;
    if (!CGSizeEqualToSize(_layer.drawableSize, size)) _layer.drawableSize = size;

    // 進行（Effekseer は 60fps 基準のフレーム数）
    simd_float3 eye = cameraWorld.columns[3].xyz;
    Effekseer::Manager::LayerParameter layer;
    layer.ViewerPosition = Effekseer::Vector3D(eye.x, eye.y, eye.z);
    _manager->SetLayerParameter(0, layer);
    Effekseer::Manager::UpdateParameter update;
    update.DeltaFrame = (float)(dt * 60.0);
    update.UpdateInterval = 1.0f;
    _manager->Update(update);
    _time += dt;

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

    _pool->NewFrame();
    EffekseerRendererMetal::BeginCommandList(_commandList);
    _renderer->SetCommandList(_commandList);
    EffekseerRendererMetal::BeginRenderPass(_commandList, enc);

    float aspect = (float)(size.width / size.height);
    Effekseer::Matrix44 proj;
    proj.PerspectiveFovRH(fov, aspect, zNear, zFar);
    _renderer->SetProjectionMatrix(proj);
    _renderer->SetCameraMatrix(ToEfk(simd_inverse(cameraWorld)));
    _renderer->SetTime((float)_time);
    _renderer->BeginRendering();
    Effekseer::Manager::DrawParameter draw;
    draw.ZNear = 0.0f;
    draw.ZFar = 1.0f;
    draw.ViewProjectionMatrix = _renderer->GetCameraProjectionMatrix();
    _manager->Draw(draw);
    _renderer->EndRendering();

    EffekseerRendererMetal::EndRenderPass(_commandList);
    _renderer->SetCommandList(nullptr);
    EffekseerRendererMetal::EndCommandList(_commandList);
    [enc endEncoding];
    [cb presentDrawable:drawable];
    [cb commit];
}

@end
