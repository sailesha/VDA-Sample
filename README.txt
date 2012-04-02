This sample code shows how use hardware decoding to play video on the Mac. It uses VideoDecodeAcceleration.framework.

This VDA API doesn't parse the video stream so this is done using FFmpeg.

To build the sample code do the following:
  1. Install FFmpeg. For example
    A. Download download FFmpeg 0.10.2 from:
       http://ffmpeg.org/releases/ffmpeg-0.10.2.tar.gz
    B. cd ffmpeg-0.10.2
    C. ./configure --enable-shared --disable-mmx --arch=x86_64
    D. make
    E. sudo make install
  2. Build video_cpu and video_gpu
  3. Download an mpeg4 video. For example: http://goo.gl/Mw5yw
  4. Run the player:
     video_cpu 46823549.mp4
     video_gpu 46823549.mp4
