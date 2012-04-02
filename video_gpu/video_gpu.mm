// Sample code to play a video file using hardware decoding.
// This is free software released into the public domain.

#import <Cocoa/Cocoa.h>
#include <VideoDecodeAcceleration/VDADecoder.h>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
}
#include <list>
#import "IOSurfaceTestView.h"
#include "util.h"

NSString* const kDisplayTimeKey = @"display_time";
const int MAX_DECODE_QUEUE_SIZE = 5;
const int MAX_PLAY_QUEUE_SIZE = 5;

class GPUDecoder {
 public:
  struct DecodedImage {
    CVImageBufferRef image;
    int64_t display_time;
  };

  GPUDecoder() : vda_decoder_(NULL),
                 pending_image_count_(0),
                 is_waiting_(false) {
    assert(pthread_mutex_init(&mutex_, NULL) == 0);
    assert(pthread_cond_init(&frame_ready_condition_, NULL) == 0);
  }

  ~GPUDecoder() {
    pthread_mutex_destroy(&mutex_);
    pthread_cond_destroy(&frame_ready_condition_);
    VDADecoderDestroy(vda_decoder_);
  }

  void Create(int width, int height, OSType source_format,
              uint8_t* avc_bytes, int avc_size) {
    NSMutableDictionary* config = [NSMutableDictionary dictionary];
    [config setObject:[NSNumber numberWithInt:width]
               forKey:(NSString*)kVDADecoderConfiguration_Width];
    [config setObject:[NSNumber numberWithInt:height]
               forKey:(NSString*)kVDADecoderConfiguration_Height];
    [config setObject:[NSNumber numberWithInt:source_format]
               forKey:(NSString*)kVDADecoderConfiguration_SourceFormat];
    assert(avc_bytes);
    NSData* avc_data = [NSData dataWithBytes:avc_bytes length:avc_size];
    [config setObject:avc_data
               forKey:(NSString*)kVDADecoderConfiguration_avcCData];

    NSMutableDictionary* format_info = [NSMutableDictionary dictionary];
    // This format is used by the CGLTexImageIOSurface2D call in IOSurfaceTestView.
    [format_info setObject:[NSNumber numberWithInt:kCVPixelFormatType_422YpCbCr8]
                    forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
    [format_info setObject:[NSDictionary dictionary]
                    forKey:(NSString*)kCVPixelBufferIOSurfacePropertiesKey];

    OSStatus status = VDADecoderCreate((CFDictionaryRef)config,
                                       (CFDictionaryRef)format_info, // optional
                                       (VDADecoderOutputCallback*)OnFrameReadyCallback,
                                       (void *)this,
                                       &vda_decoder_);
    if (status == kVDADecoderHardwareNotSupportedErr)
      fprintf(stderr, "hadware does not support GPU decoding\n");
    assert(status == kVDADecoderNoErr);
  }

  void DecodeNextFrame(uint8_t* bytes, int size, int64_t display_time) {
    {
      ScopedLock lock(&mutex_);
      pending_image_count_++;
    }
    NSData* data = [NSData dataWithBytes:bytes length:size];
    NSMutableDictionary* frame_info = [NSMutableDictionary dictionary];
    [frame_info setObject:[NSNumber numberWithLongLong:display_time]
                   forKey:kDisplayTimeKey];
    assert(VDADecoderDecode(vda_decoder_, 0, (CFDataRef)data,
                            (CFDictionaryRef)frame_info) == 0);
  }

  int GetDecodedImageCount() {
    ScopedLock lock(&mutex_);
    return images_.size();
  }

  DecodedImage GetNextDecodedImage() {
    ScopedLock lock(&mutex_);
    return images_.front();
  }

  DecodedImage PopNextDecodedImage() {
    ScopedLock lock(&mutex_);
    DecodedImage image = images_.front();
    images_.pop_front();
    return image;
  }

  void WaitForDecodedImage() {
    ScopedLock lock(&mutex_);
    is_waiting_ = true;
    pthread_cond_wait(&frame_ready_condition_, &mutex_);
    is_waiting_ = false;
  }

  int pending_image_count() {
    ScopedLock lock(&mutex_);
    return pending_image_count_;
  }

 private:
  static void OnFrameReadyCallback(void *callback_data,
                                   CFDictionaryRef frame_info,
                                   OSStatus status,
                                   uint32_t flags,
                                   CVImageBufferRef image_buffer) {
    ScopedPool pool;
    assert(status == 0);
    assert(image_buffer);
    assert(CVPixelBufferGetPixelFormatType(image_buffer) == '2vuy');
    CGSize size = CVImageBufferGetDisplaySize(image_buffer);
    uint64_t time = [[(NSDictionary*)frame_info objectForKey:kDisplayTimeKey]
        longLongValue];
    GPUDecoder* gpu_decoder = static_cast<GPUDecoder*>(callback_data);
    gpu_decoder->OnFrameReady(image_buffer, time);
  }

  void OnFrameReady(CVImageBufferRef image_buffer,
                    int64_t display_time) {
    ScopedLock lock(&mutex_);

    if (image_buffer) {
      DecodedImage image;
      image.image = CVBufferRetain(image_buffer);
      image.display_time = display_time;

      std::list<DecodedImage>::iterator it = images_.begin();
      while (it != images_.end() && it->display_time <= display_time)
        it++;
      images_.insert(it, image);
    }

    pending_image_count_--;
    if (is_waiting_)
      pthread_cond_signal(&frame_ready_condition_);
  }

  VDADecoder vda_decoder_;
  std::list<DecodedImage> images_;
  int pending_image_count_;
  pthread_mutex_t mutex_;
  bool is_waiting_;
  pthread_cond_t frame_ready_condition_;
};

class Video {
 public:
  Video() : format_context_(NULL),
            codec_context_(NULL),
            codec_(NULL),
            video_stream_index_(-1),
            has_reached_end_of_file_(false) {
  }

  ~Video() {
    avformat_free_context(format_context_);
  }

  void Open(const char* path) {
    av_register_all();
    assert(avformat_open_input(&format_context_, path, NULL, NULL) == 0);
    assert(avformat_find_stream_info(format_context_, NULL) >= 0);

    for (int i = 0; i < format_context_->nb_streams; ++i) {
      if (format_context_->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO) {
        video_stream_index_ = i;
        codec_context_ = format_context_->streams[i]->codec;
        break;
      }
    }
    assert(codec_context_);

    assert(codec_ = avcodec_find_decoder(codec_context_->codec_id));
    assert(avcodec_open2(codec_context_, codec_, NULL) >= 0);
  }

  bool GetNextPacket(AVPacket* packet) {
    int error = av_read_frame(format_context_, packet);
    if (error == AVERROR_EOF)
      has_reached_end_of_file_ = true;
    return error >= 0;
  }

  int width() { return codec_context_->width; }
  int height() { return codec_context_->height; }
  bool has_reached_end_of_file() { return has_reached_end_of_file_; }
  int video_stream_index() { return video_stream_index_; }
  AVStream* stream() { return format_context_->streams[video_stream_index_]; }
  AVCodecContext* codec_context() { return codec_context_; }

 private:
  AVFormatContext* format_context_;
  AVCodecContext* codec_context_;
  AVCodec* codec_;
  int video_stream_index_;
  bool has_reached_end_of_file_;
};

int main (int argc, const char * argv[]) {
  ScopedPool pool;
  [NSApplication sharedApplication];

  assert(argc == 2);
  Video video;
  video.Open(argv[1]);
  GPUDecoder gpu_decoder;
  gpu_decoder.Create(video.width(), video.height(), 'avc1',
                     video.codec_context()->extradata,
                     video.codec_context()->extradata_size);

  NSRect rect = NSMakeRect(0, 0, video.width(), video.height());
  NSWindow* window = [[[NSWindow alloc]
      initWithContentRect:rect
      styleMask:NSTitledWindowMask
      backing:NSBackingStoreBuffered
      defer:NO] autorelease];
  [window center];
  [window makeKeyAndOrderFront:nil];
  [window retain];

  NSView* content_view = [window contentView];
  IOSurfaceTestView* view = [[[IOSurfaceTestView alloc]
      initWithFrame:[content_view bounds]] autorelease];
  [content_view addSubview:view];
  [view retain];

  DisplayClock clock(video.stream()->time_base);
  clock.Start();

  while (!video.has_reached_end_of_file()) {
    ScopedPool pool2;

    // Block until an image is decoded.
    if (gpu_decoder.pending_image_count() >= MAX_DECODE_QUEUE_SIZE &&
        gpu_decoder.GetDecodedImageCount() == 0) {
      gpu_decoder.WaitForDecodedImage();
    }

    // Decode images until it's time to display something.
    while (gpu_decoder.pending_image_count() < MAX_DECODE_QUEUE_SIZE &&
           gpu_decoder.GetDecodedImageCount() < MAX_PLAY_QUEUE_SIZE) {
      if (gpu_decoder.GetDecodedImageCount() > 0 &&
          clock.CurrentDisplayTime() >= gpu_decoder.GetNextDecodedImage().display_time) {
          break;
      }

      AVPacket packet;
      if (video.GetNextPacket(&packet)) {
        if (packet.stream_index == video.video_stream_index())
          gpu_decoder.DecodeNextFrame(packet.data, packet.size, packet.pts);
        av_free_packet(&packet);
      }
    }

    // Display an image.
    if (gpu_decoder.GetDecodedImageCount() > 0) {
      GPUDecoder::DecodedImage image = gpu_decoder.PopNextDecodedImage();
      [[NSRunLoop currentRunLoop] runUntilDate:
          clock.DisplayTimeToNSDate(image.display_time)];

      [view setImage:image.image];
      [view setNeedsDisplay:YES];
      CVBufferRelease(image.image);
    }
  }

  return 0;
}