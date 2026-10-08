#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

// 担当: Effekseer（C++ / Metal ランタイム）への橋渡し。ヘッダは Objective-C のみ（C++ は .mm の中に閉じる）。
// ゲームの 3D 画面（RealityKit）の上に、透明な CAMetalLayer を重ねて Effekseer の効果を描く。
// 座標系は右手系・Y 上向き・1 単位 = 1 m（RealityKit のワールドと同じ）。

/// 効果 1 つ分の再生の記録（停止・移動に使う）。
typedef int32_t EfkHandle;

@interface EfkRuntime : NSObject

/// 重ねて描く Metal レイヤー（呼び出し側で親ビューへ add し、frame / contentsScale を合わせる）。
@property (nonatomic, readonly) CAMetalLayer *layer;
/// 読み込み済みの効果の数。
@property (nonatomic, readonly) NSInteger loadedCount;
/// 再生中の効果の数（遅延・ループ中を含む）。
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

/// 1 フレーム進めて描く。cameraWorld はカメラのワールド行列（RealityKit の transformMatrix(relativeTo: nil)）、
/// verticalFOV はラジアン。deltaSeconds だけ進める（Effekseer は 60fps 基準のフレームへ換算する）。
- (void)renderWithCameraWorld:(simd_float4x4)cameraWorld
                  verticalFOV:(float)verticalFOV
                         near:(float)zNear
                          far:(float)zFar
                 deltaSeconds:(double)deltaSeconds
                 drawableSize:(CGSize)drawableSize;

@end

NS_ASSUME_NONNULL_END
