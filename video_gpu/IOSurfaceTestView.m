/*
 *  IOSurfaceTestView.m
 *  IOSurfaceTest
 *
 *  Created by Paolo on 21/09/2009.
 *
 * Copyright (c) 2009 Paolo Manna
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice, this list of
 *   conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice, this list of
 *   conditions and the following disclaimer in the documentation and/or other materials
 *   provided with the distribution.
 * - Neither the name of the Author nor the names of its contributors may be used to
 *   endorse or promote products derived from this software without specific prior written
 *   permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS
 * OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 * ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#import "IOSurfaceTestView.h"
#import <OpenGL/CGLMacro.h>
#import <OpenGL/CGLIOSurface.h>


@implementation IOSurfaceTestView

- (NSOpenGLPixelFormat*) basicPixelFormat
{
    NSOpenGLPixelFormatAttribute	mAttrs []	= {
		NSOpenGLPFAWindow,
		NSOpenGLPFADoubleBuffer,
		NSOpenGLPFAAccelerated,
		NSOpenGLPFANoRecovery,
		NSOpenGLPFAColorSize,		(NSOpenGLPixelFormatAttribute)32,
		NSOpenGLPFAAlphaSize,		(NSOpenGLPixelFormatAttribute)8,
		NSOpenGLPFADepthSize,		(NSOpenGLPixelFormatAttribute)24,
		(NSOpenGLPixelFormatAttribute) 0
	};
	
	return [[[NSOpenGLPixelFormat alloc] initWithAttributes: mAttrs] autorelease];
}

- (id)initWithFrame:(NSRect)frameRect
{
	if (self = [super initWithFrame: frameRect pixelFormat: [self basicPixelFormat]]) {
		CGLContextObj   cgl_ctx			= [[self openGLContext]  CGLContextObj];
		long			swapInterval	= 1;
		
		[[self openGLContext] setValues:(GLint*)(&swapInterval)
						   forParameter: NSOpenGLCPSwapInterval];
		glEnable(GL_TEXTURE_RECTANGLE_ARB);
		glGenTextures(1, &_surfaceTexture);
		glDisable(GL_TEXTURE_RECTANGLE_ARB);
	}
	
	return self;
}

- (void)dealloc
{
	CGLContextObj   cgl_ctx = [[self openGLContext]  CGLContextObj];
	
	glDeleteTextures(1, &_surfaceTexture);

  if (image_)
    CFRelease(image_);

	[super dealloc];
}

- (void)_bindSurfaceToTexture: (IOSurfaceRef)aSurface
{
	if (_surface && (_surface != aSurface)) {
		CFRelease(_surface);
	}
	
	if ((_surface = aSurface) != nil) {
		CGLContextObj   cgl_ctx = [[self openGLContext]  CGLContextObj];
		
		_texWidth	= IOSurfaceGetWidth(_surface);
		_texHeight	= IOSurfaceGetHeight(_surface);
		
		glEnable(GL_TEXTURE_RECTANGLE_ARB);
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _surfaceTexture);
		CGLTexImageIOSurface2D(cgl_ctx, GL_TEXTURE_RECTANGLE_ARB, GL_RGB8,
							   _texWidth, _texHeight,
							   GL_YCBCR_422_APPLE, GL_UNSIGNED_SHORT_8_8_APPLE, _surface, 0);
//		CGLTexImageIOSurface2D(cgl_ctx, GL_TEXTURE_RECTANGLE_ARB, GL_RGBA8,
//							   _texWidth, _texHeight,
//							   GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _surface, 0);
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, 0);
		glDisable(GL_TEXTURE_RECTANGLE_ARB);
    
    glFlush();
	}
}

- (void)setImage:(CVPixelBufferRef)image
{
  if (image_)
    CFRelease(image_);
  image_ = CVBufferRetain(image);

  IOSurfaceRef io_surface = CVPixelBufferGetIOSurface(image);
  // _bindSurfaceToTexture assumes that the surface is retained.
  CFRetain(io_surface);
  [self _bindSurfaceToTexture:io_surface];
}

- (void)setSurfaceID: (IOSurfaceID)anID
{
	if (anID) {
    // Note, IOSurfaceLookup retains the surface ref.
		[self _bindSurfaceToTexture: IOSurfaceLookup(anID)];
	}
}

- (void)reshape
{
 	CGLContextObj   cgl_ctx = [[self openGLContext]  CGLContextObj];
	
	glViewport(0, 0, [self bounds].size.width, [self bounds].size.height);
    
    glClearColor(1.0, 0.0, 0.0, 0.0);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	
	[[self openGLContext] flushBuffer];
}

- (void)drawRect:(NSRect)rect
{
#pragma unused(rect)
 	CGLContextObj   cgl_ctx		= [[self openGLContext]  CGLContextObj];
	
	//Clear background
	glClearColor(1.0, 0.0, 0.0, 0.0);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	
	if (_surface) {
		GLfloat		texMatrix[16]	= {0};
		GLint		saveMatrixMode;
		
		// Reverses and normalizes the texture
		texMatrix[0]	= (GLfloat)_texWidth;
		texMatrix[5]	= -(GLfloat)_texHeight;
		texMatrix[10]	= 1.0;
		texMatrix[13]	= (GLfloat)_texHeight;
		texMatrix[15]	= 1.0;
		
		glGetIntegerv(GL_MATRIX_MODE, &saveMatrixMode);
		glMatrixMode(GL_TEXTURE);
		glPushMatrix();
		glLoadMatrixf(texMatrix);
		glMatrixMode(saveMatrixMode);
		
		glEnable(GL_TEXTURE_RECTANGLE_ARB);
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _surfaceTexture);
		glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
	} else {
		glColor4f(0.4, 0.4, 0.4, 0.4);
	}
	
	//Draw textured quad
	glBegin(GL_QUADS);
		glTexCoord2f(0.0, 0.0);
		glVertex3f(-1.0, -1.0, 0.0);
		glTexCoord2f(1.0, 0.0);
		glVertex3f(1.0, -1.0, 0.0);
		glTexCoord2f(1.0, 1.0);
		glVertex3f(1.0, 1.0, 0.0);
		glTexCoord2f(0.0, 1.0);
		glVertex3f(-1.0, 1.0, 0.0);
	glEnd();
	
	//Restore texturing settings
	if (_surface) {
		GLint		saveMatrixMode;
		
		glDisable(GL_TEXTURE_RECTANGLE_ARB);
		
		glGetIntegerv(GL_MATRIX_MODE, &saveMatrixMode);
		glMatrixMode(GL_TEXTURE);
		glPopMatrix();
		glMatrixMode(saveMatrixMode);
	}
	
	[[self openGLContext] flushBuffer];
}

@end
