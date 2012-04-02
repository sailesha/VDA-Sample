// Sample code to play a video file using software decoding.
// This is free software released into the public domain.

#import <Cocoa/Cocoa.h>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
}
#include "util.h"

class Video {
 public:
  Video() : format_context_(NULL),
            codec_context_(NULL),
            codec_(NULL),
            video_stream_index_(-1),
            frame_(NULL),
            frame_rgb_(NULL),
            image_convert_context_(NULL),
            current_frame_display_time_(0),
            has_reached_end_of_file_(false) {
  }

  ~Video() {
    sws_freeContext(image_convert_context_);
    free(frame_rgb_->data[0]);
    av_free(frame_rgb_);
    av_free(frame_);
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

    assert(frame_ = avcodec_alloc_frame());

    assert(frame_rgb_ = avcodec_alloc_frame());
    int numBytes = avpicture_get_size(PIX_FMT_RGB24, width(), height());
    uint8_t* buffer = (uint8_t*)av_malloc(numBytes * sizeof(uint8_t));
    avpicture_fill((AVPicture*)frame_rgb_, buffer, PIX_FMT_RGB24, width(), height());

    assert(image_convert_context_ = sws_getContext(width(), height(),
        codec_context_->pix_fmt, width(), height(), PIX_FMT_RGB24, SWS_BICUBIC,
        NULL, NULL, NULL));
  }

  bool DecodeNextFrame() {
    AVPacket packet;
    int error = av_read_frame(format_context_, &packet);
    if (error < 0) {
      if (error == AVERROR_EOF)
        has_reached_end_of_file_ = true;
      return false;
    }

    int got_picture = 0;
    if (packet.stream_index == video_stream_index_) {
      assert(avcodec_decode_video2(codec_context_, frame_, &got_picture, &packet) >= 0);
      if (got_picture) {
        assert(sws_scale(image_convert_context_, frame_->data, frame_->linesize,
               0, height(), frame_rgb_->data, frame_rgb_->linesize) > 0);
        current_frame_display_time_ = packet.pts;
      }
    }
    av_free_packet(&packet);
    return got_picture != 0;
  }

  int width() { return codec_context_->width; }
  int height() { return codec_context_->height; }
  bool has_reached_end_of_file() { return has_reached_end_of_file_; }
  AVFrame* current_frame_rgb() { return frame_rgb_; }
  int64_t current_frame_display_time() { return current_frame_display_time_; }
  AVStream* stream() { return format_context_->streams[video_stream_index_]; }

 private:
  AVFormatContext* format_context_;
  AVCodecContext* codec_context_;
  AVCodec* codec_;
  int video_stream_index_;
  AVFrame* frame_;
  AVFrame* frame_rgb_;
  SwsContext* image_convert_context_;
  int64_t current_frame_display_time_;
  bool has_reached_end_of_file_;
};

NSImage* AVFrameToNSImage(AVFrame* frame, int width, int height) {
  NSBitmapImageRep* rep = [[[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes:NULL
      pixelsWide:width
      pixelsHigh:height
      bitsPerSample:8
      samplesPerPixel:3
      hasAlpha:NO
      isPlanar:NO
      colorSpaceName:NSCalibratedRGBColorSpace
      bytesPerRow:frame->linesize[0]
      bitsPerPixel:24] autorelease];
  memcpy([rep bitmapData], frame->data[0], frame->linesize[0] * height);
  NSImage* image = [[[NSImage alloc]
      initWithSize:NSMakeSize(width, height)] autorelease];
  [image addRepresentation:rep];
  return image;
}

int main (int argc, const char * argv[]) {
  ScopedPool pool;
  [NSApplication sharedApplication];

  assert(argc == 2);
  Video video;
  video.Open(argv[1]);

  NSRect rect = NSMakeRect(0, 0, video.width(), video.height());
  NSWindow* window = [[[NSWindow alloc]
      initWithContentRect:rect
      styleMask:NSTitledWindowMask
      backing:NSBackingStoreBuffered
      defer:NO] autorelease];
  [window center];
  [window makeKeyAndOrderFront:nil];

  NSView* content_view = [window contentView];
  NSImageView* view = [[[NSImageView alloc]
      initWithFrame:[content_view bounds]] autorelease];
  [content_view addSubview:view];

  DisplayClock clock(video.stream()->time_base);
  clock.Start();

  while (!video.has_reached_end_of_file()) {
    if (!video.DecodeNextFrame())
      continue;

    ScopedPool pool2;
    [[NSRunLoop currentRunLoop] runUntilDate:
        clock.DisplayTimeToNSDate(video.current_frame_display_time())];

    NSImage* image = AVFrameToNSImage(
        video.current_frame_rgb(), video.width(), video.height());
    [view setImage:image];
  }

  return 0;
}