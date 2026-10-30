#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Audio chunk delivered while generating. `samples` is little-endian float32,
/// already copied out of the engine's transient buffer, at `sampleRate` Hz mono.
/// Set `*stop = YES` to abort the rest of the generation.
typedef void (^BreezeChunkBlock)(NSData *samples, BOOL *stop);

/// Thin Objective-C wrapper over the C ABI in `breeze/breeze.h`.
///
/// Why a wrapper instead of calling the C API from Swift directly: the request
/// struct has a fixed C layout and the audio callback is a bare function
/// pointer. Building that in Swift is fragile, so the layout is filled here and
/// Swift only ever sees Foundation types.
@interface BreezeEngine : NSObject

/// Loads a GGUF into memory. Blocking; call it off the main thread.
/// `useGPU` = YES makes ggml pick Metal on Apple platforms and fall back to CPU.
/// Returns nil on failure; see `+lastErrorMessage`.
- (nullable instancetype)initWithModelPath:(NSString *)path
                                    useGPU:(BOOL)useGPU NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/// Model sample rate in Hz (currently 24000). Reference audio must match this.
@property (nonatomic, readonly) NSInteger sampleRate;

/// True while a generation is in flight. The C context is not reentrant.
@property (nonatomic, readonly) BOOL busy;

/// The backend the engine actually ended up on ("CPU", "Metal", ...). The request
/// only says what we asked for; a Metal init failure silently falls back to CPU.
@property (nonatomic, readonly) NSString *backendName;

/// Vocoder flush size in codec frames. 0 keeps the engine default (streaming:
/// a tiny first flush, then ~25 frames), which re-decodes the sliding window of
/// left context on every flush. Since this app collects the whole clip before it
/// plays, we can decode in one go and skip that repeated work — measurably
/// faster, at the cost of no audio until the end.
@property (nonatomic) NSInteger chunkFrames;

/// Blocking generation, streams float32 chunks to `onChunk` on the calling
/// thread. Returns YES on success. Guarded by an internal lock, so a second
/// concurrent call will block rather than crash.
- (BOOL)generateWithText:(NSString *)text
             instruction:(nullable NSString *)instruction
                 refText:(nullable NSString *)refText
         refAudioSamples:(nullable NSData *)refAudioSamples
                cfgScale:(float)cfgScale
                    seed:(NSInteger)seed
            maxNewTokens:(NSInteger)maxNewTokens
              splitChars:(NSInteger)splitChars
             temperature:(float)temperature
                    topK:(NSInteger)topK
                    topP:(float)topP
       repetitionPenalty:(float)repetitionPenalty
                 onChunk:(nullable BreezeChunkBlock)onChunk;

/// Convenience path that writes a 16-bit PCM WAV instead of streaming.
- (BOOL)generateWAVWithText:(NSString *)text
                instruction:(nullable NSString *)instruction
                    refText:(nullable NSString *)refText
            refAudioSamples:(nullable NSData *)refAudioSamples
                   cfgScale:(float)cfgScale
                       seed:(NSInteger)seed
               maxNewTokens:(NSInteger)maxNewTokens
                 splitChars:(NSInteger)splitChars
                temperature:(float)temperature
                       topK:(NSInteger)topK
                       topP:(float)topP
          repetitionPenalty:(float)repetitionPenalty
                    outPath:(NSString *)outPath;

/// Frees the context. Safe to call more than once.
- (void)shutdown;

/// Last engine-side failure on the current thread, for logging.
+ (NSString *)lastErrorMessage;

@end

NS_ASSUME_NONNULL_END
