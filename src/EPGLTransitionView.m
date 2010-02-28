/* ===========================================================================
 
 Copyright (c) 2010 Edward Patel
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 
 =========================================================================== */

#import <OpenGLES/ES1/glext.h>

#import "EPGLTransitionView.h"

@implementation EPGLTransitionView

@synthesize animating;
@dynamic transitionFrameInterval;

+ (Class) layerClass
{
    return [CAEAGLLayer class];
}

- (id)initWithWindow:(UIView*)view 
			delegate:(id<EPGLTransitionViewDelegate>)_delegate;
{
    if ((self = [super initWithFrame:view.frame]))
	{
		size = view.frame.size;
		delegate = _delegate;
		[delegate retain];		
		[self setClearColorRed:0.0
						 green:0.0
						  blue:0.0
						 alpha:0.0];
		
		// Get a image of the screen
		UIGraphicsBeginImageContext(view.bounds.size);
		[view.layer renderInContext:UIGraphicsGetCurrentContext()];
		UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();

		// Allocate some memory for the texture
		GLubyte *textureData = (GLubyte*)calloc(512*4, 512);
		
		// Create a drawing context to draw image into texture memory
		CGContextRef textureContext = CGBitmapContextCreate(textureData, 
														   512, 
														   512, 
														   8, 
														   512*4, 
														   CGImageGetColorSpace(image.CGImage),	
														   kCGImageAlphaPremultipliedLast);
		CGContextDrawImage(textureContext, 
						   CGRectMake(0, 512-size.height, size.width, size.height), 
						   image.CGImage);
		CGContextRelease(textureContext);
		// ...done creating the texture data

		CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
        
		self.userInteractionEnabled = NO;

        eaglLayer.opaque = NO;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
										[NSNumber numberWithBool:NO], kEAGLDrawablePropertyRetainedBacking, 
										kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
		
		// Create a renderer with texture data for a screen shot
		context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
        
        if (!context || ![EAGLContext setCurrentContext:context])
		{
            [self release];
            return nil;
        }
		
		glGenTextures(1, &textureFromView);
		glBindTexture(GL_TEXTURE_2D, textureFromView);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 512, 512, 0, GL_RGBA, GL_UNSIGNED_BYTE, textureData);
		
		// free texture data which is by now copied into the GL context
		free(textureData);
 
		glGenFramebuffersOES(1, &defaultFramebuffer);
		glGenRenderbuffersOES(1, &colorRenderbuffer);
		glBindFramebufferOES(GL_FRAMEBUFFER_OES, defaultFramebuffer);
		glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
		glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, 
									 GL_COLOR_ATTACHMENT0_OES, 
									 GL_RENDERBUFFER_OES, 
									 colorRenderbuffer);
		
		glViewport(0, 0, size.width, size.height);
		
		glMatrixMode(GL_TEXTURE);
		glLoadIdentity();
		glScalef(size.width/512.0, size.height/512.0, 1.0); // Convert to screen part of the 512x512 texture
		glMatrixMode(GL_MODELVIEW);

		// setup delegate now when GL context is active
		[delegate setupTransition];
		       
		[view.window addSubview:self];

		animating = FALSE;
		displayLinkSupported = FALSE;
		transitionFrameInterval = 1;
		displayLink = nil;
		animationTimer = nil;
		
		// A system version of 3.1 or greater is required to use CADisplayLink. The NSTimer
		// class is used as fallback when it isn't available.
		NSString *reqSysVer = @"3.1";
		NSString *currSysVer = [[UIDevice currentDevice] systemVersion];
		if ([currSysVer compare:reqSysVer options:NSNumericSearch] != NSOrderedAscending)
			displayLinkSupported = TRUE;
    }
	
    return self;
}

- (void) prepareTextureTo:(UIView*)view
{
	// Get a image of the screen
	UIGraphicsBeginImageContext(view.bounds.size);
	[view.layer renderInContext:UIGraphicsGetCurrentContext()];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	
	// Allocate some memory for the texture
	GLubyte *textureData = (GLubyte*)calloc(512*4, 512);
	
	// Create a drawing context to draw image into texture memory
	CGContextRef textureContext = CGBitmapContextCreate(textureData, 
														512, 
														512, 
														8, 
														512*4, 
														CGImageGetColorSpace(image.CGImage),	
														kCGImageAlphaPremultipliedLast);
	CGContextDrawImage(textureContext, 
					   CGRectMake(0, 512-size.height, size.width, size.height), 
					   image.CGImage);
	CGContextRelease(textureContext);
	// ...done creating the texture data

	[EAGLContext setCurrentContext:context];
	
	glGenTextures(1, &textureToView);
	glBindTexture(GL_TEXTURE_2D, textureToView);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 512, 512, 0, GL_RGBA, GL_UNSIGNED_BYTE, textureData);

	// free texture data which is by now copied into the GL context
	free(textureData);
}

- (NSInteger) transitionFrameInterval
{
	return transitionFrameInterval;
}

- (void)stopTransition
{
	if (animating)
	{
		if (displayLinkSupported)
		{
			[displayLink invalidate];
			displayLink = nil;
		}
		else
		{
			[animationTimer invalidate];
			animationTimer = nil;
		}
		
		animating = FALSE;
	}
}

- (void) setTransitionFrameInterval:(NSInteger)frameInterval
{
	if (frameInterval >= 1)
	{
		transitionFrameInterval = frameInterval;
		
		if (animating)
		{
			[self stopTransition];
			[self startTransition];
		}
	}
}

- (void) startTransition
{
	if (!animating)
	{
		if (displayLinkSupported)
		{			
			displayLink = [NSClassFromString(@"CADisplayLink") displayLinkWithTarget:self selector:@selector(drawView:)];
			[displayLink setFrameInterval:transitionFrameInterval];
			[displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
		}
		else
			animationTimer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)((1.0 / 60.0) * transitionFrameInterval) target:self selector:@selector(drawView:) userInfo:nil repeats:TRUE];
		
		animating = TRUE;
	}
}

- (void) dealloc
{
	[delegate release];
	
	if (defaultFramebuffer)
	{
		glDeleteFramebuffersOES(1, &defaultFramebuffer);
		defaultFramebuffer = 0;
	}
	
	if (colorRenderbuffer)
	{
		glDeleteRenderbuffersOES(1, &colorRenderbuffer);
		colorRenderbuffer = 0;
	}
	
	if ([EAGLContext currentContext] == context)
        [EAGLContext setCurrentContext:nil];
	
	[context release];
	context = nil;
	
    [super dealloc];
}

- (BOOL) render
{
    [EAGLContext setCurrentContext:context];
    
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, defaultFramebuffer);
	
	glClearColor(clearColor[0], 
				 clearColor[1], 
				 clearColor[2], 
				 clearColor[3]);
    glClear(GL_COLOR_BUFFER_BIT);
    
	glEnable(GL_TEXTURE_2D);
	glBindTexture(GL_TEXTURE_2D, textureFromView);
	
	BOOL drawOK = [delegate drawTransitionFrameWithTextureFrom:textureFromView
													 textureTo:textureToView];
    
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
    [context presentRenderbuffer:GL_RENDERBUFFER_OES];
	
	return drawOK;
}

- (BOOL) resizeFromLayer:(CAEAGLLayer *)layer
{	
	
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
    [context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:layer];
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
	
    if (glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES)
	{
		NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
        return NO;
    }
    
    return YES;
}

- (void) drawView:(id)sender
{
	if ([self render] == NO) {
		[self stopTransition];
		[self removeFromSuperview];
	}
}

- (void) layoutSubviews
{
	[self resizeFromLayer:(CAEAGLLayer*)self.layer];
    [self drawView:nil];
}

- (void) setClearColorRed:(GLfloat)red 
					green:(GLfloat)green
					 blue:(GLfloat)blue
					alpha:(GLfloat)alpha
{
	clearColor[0] = red;
	clearColor[1] = green;
	clearColor[2] = blue;
	clearColor[3] = alpha;
	if (alpha > 0.9) {
		CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
		eaglLayer.opaque = YES;
	}
}

@end

