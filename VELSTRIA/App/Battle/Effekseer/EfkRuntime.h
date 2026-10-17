#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

// 担当: Effekseer（C++ / Metal ランタイム）への橋渡し。ヘッダは Objective-C のみ（C++ は .mm の中に閉じる）。
// 描き方は 2 通り（docs/EFFEKSEER.md「描画の 2 つの経路」）:
//   重ね描き: ゲームの 3D 画面（RealityKit）の上に、透明な CAMetalLayer を重ねて描く（シミュレータ・低画質・後処理の準備前）。
//   後処理の中: RealityKit の postProcess（PostProcessor）の中で、3D 画面の色と深度を写した画へ描く（3D に隠れる・ブルームが掛かる・
//              歪みは 3D 画面を背景に使う）。進める（Update）のはメインスレッド、描く（Draw）のは描画スレッド。間は錠で守る。
// 座標系は右手系・Y 上向き・1 単位 = 1 m（RealityKit のワールドと同じ）。

/// 効果 1 つ分の再生の記録（停止・移動に使う）。
typedef int32_t EfkHandle;

@interface EfkRuntime : NSObject

/// 重ねて描く Metal レイヤー（呼び出し側で親ビューへ add し、frame / contentsScale を合わせる）。
@property (nonatomic, readonly) CAMetalLayer *layer;
/// 読み込み済みの効果の数。
@property (nonatomic, readonly) NSInteger loadedCount;
/// 再生中の効果の数（遅延・ループ中を含む）。どのスレッドからでもよい。
@property (nonatomic, readonly) NSInteger activeCount;

/// Metal が使えない環境では nil。
- (nullable instancetype)init;

/// .efk（Effekseer の書き出し）を読み込んで name で引けるようにする。テクスチャ等は .efk と同じ相対位置から読む。
- (BOOL)loadEffectNamed:(NSString *)name path:(NSString *)path magnification:(float)magnification;
- (BOOL)hasEffectNamed:(NSString *)name;

/// 再生する。yaw はワールドの Y 軸まわり（ラジアン）、scale は一様倍率、speed は再生速度（1 = 等倍）。失敗時は -1。
- (EfkHandle)playNamed:(NSString *)name position:(simd_float3)position yaw:(float)yaw scale:(float)scale speed:(float)speed;
- (void)setPosition:(simd_float3)position yaw:(float)yaw forHandle:(EfkHandle)handle;
- (void)setLocation:(simd_float3)position forHandle:(EfkHandle)handle;
- (void)stopHandle:(EfkHandle)handle;
- (void)stopAll;
- (BOOL)isPlayingHandle:(EfkHandle)handle;
/// 3D の上に描くか（YES）、3D に隠れるか（NO = 再生の既定）。重ね描きでは違いは無い（どちらも 3D の上）。
/// 後処理の中では、隠れる層を描いた後に深度を遠くへ戻して（resetDepth）上の層を描く。
- (void)setOnTop:(BOOL)onTop forHandle:(EfkHandle)handle NS_SWIFT_NAME(setOnTop(_:handle:));

// MARK: 重ね描き（メインスレッド）

/// 1 フレーム進めて重ねのレイヤーへ描く。cameraWorld はカメラのワールド行列（RealityKit の transformMatrix(relativeTo: nil)）、
/// verticalFOV はラジアン。deltaSeconds だけ進める（Effekseer は 60fps 基準のフレームへ換算する）。
- (void)renderWithCameraWorld:(simd_float4x4)cameraWorld
                  verticalFOV:(float)verticalFOV
                         near:(float)zNear
                          far:(float)zFar
                 deltaSeconds:(double)deltaSeconds
                 drawableSize:(CGSize)drawableSize;

// MARK: 後処理の中で描く

/// 後処理の中で描く間（メインスレッドが毎フレーム決める）。YES の間は重ねのレイヤーへ描かず、後処理が描く。
/// NO → YES で重ねのレイヤーを空にして隠し、YES → NO で見せる。どのスレッドからでも読める。
@property (atomic) BOOL drawsInPostProcess;

/// 1 フレーム進め、後処理が描くときのカメラを覚える（メインスレッド。描くのは後処理）。
- (void)advanceWithCameraWorld:(simd_float4x4)cameraWorld deltaSeconds:(double)deltaSeconds
    NS_SWIFT_NAME(advance(cameraWorld:deltaSeconds:));

/// 後処理の描画先（色の形式・深度の向き）に合わせた描き手があるか（描画スレッド）。無ければ背景で作り始めて NO
/// （作り終えるまでは重ね描きのまま）。深度は Depth32Float、reversedDepth = 近いほど大きい（RealityKit の逆 Z）。
- (BOOL)isPreparedForPostColorFormat:(MTLPixelFormat)format reversedDepth:(BOOL)reversedDepth
    NS_SWIFT_NAME(isPrepared(postColorFormat:reversedDepth:));

/// 後処理の中で描く（描画スレッド）。encoder は色 = isPrepared の形式・深度 = Depth32Float（3D 画面の深度を写したもの）の
/// パス。projection は 3D 画面の射影（PostProcessContext.projection。深度が一致する）。background は歪みの背景
/// （効果を描く前の 3D 画面。nil なら歪みは何も映さない）。resetDepth は 3D に隠れる層を描いた後に同じ encoder で深度を
/// 遠くへ戻す処理（nil なら 3D の上の層は描かない）。描いたら YES。
- (BOOL)encodePostWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                   projection:(simd_float4x4)projection
                   background:(nullable id<MTLTexture>)background
                   resetDepth:(void (^_Nullable)(id<MTLRenderCommandEncoder>))resetDepth
    NS_SWIFT_NAME(encodePost(encoder:projection:background:resetDepth:));

/// 確認用: 重ね描きの描き手で encoder（BGRA8Unorm・深度なし）へ描く（後処理の経路と比べる基準。進めない）。
- (BOOL)debugEncodeOverlayWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                          cameraWorld:(simd_float4x4)cameraWorld
                           projection:(simd_float4x4)projection
    NS_SWIFT_NAME(debugEncodeOverlay(encoder:cameraWorld:projection:));

/// 射影行列が逆 Z（近いほど深度が大きい）か（純粋。単体テスト対象）。
+ (BOOL)isReversedDepthProjection:(simd_float4x4)projection NS_SWIFT_NAME(isReversedDepth(projection:));

@end

NS_ASSUME_NONNULL_END
