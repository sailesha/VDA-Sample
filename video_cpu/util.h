// Utility classes.
// This is free software released into the public domain.

#include <Cocoa/Cocoa.h>
#include <pthread.h>
extern "C" {
#include <libavutil/rational.h>
}

class ScopedLock {
 public:
  ScopedLock(pthread_mutex_t* mutex) : mutex_(mutex) { pthread_mutex_lock(mutex_); }
  ~ScopedLock() { pthread_mutex_unlock(mutex_); }
 private:
  pthread_mutex_t* const mutex_;
};

class ScopedPool {
 public:
  ScopedPool() {
    pool_ = [[NSAutoreleasePool alloc] init];
  }
  ~ScopedPool() {
    [pool_ drain];
  }
 private:
  NSAutoreleasePool* pool_;
};

class DisplayClock {
 public:
  DisplayClock(const AVRational& time_unit) : time_unit_(time_unit),
                                              start_time_(0) {
  }

  void Start() {
    start_time_ = CFAbsoluteTimeGetCurrent();
  }

  int64_t CurrentDisplayTime() {
    CFTimeInterval delta = CFAbsoluteTimeGetCurrent() - start_time_;
    return (delta * time_unit_.den) / time_unit_.num;
  }

  NSDate* DisplayTimeToNSDate(int64_t pts) {
    CFTimeInterval seconds =
        ((CFTimeInterval)(pts * time_unit_.num)) / (CFTimeInterval)time_unit_.den;
    NSDate* date = (NSDate*)CFDateCreate(NULL, start_time_ + seconds);
    return [date autorelease];
  }

 private:
  const AVRational time_unit_;
  CFAbsoluteTime start_time_;
};
