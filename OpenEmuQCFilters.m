/*
 Copyright (c) 2009, OpenEmu Team
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

// #import <OpenGL/CGLMacro.h>

#import "OEFilterPlugin.h"
#import "OEGameShader.h"
#import "OpenEmuQCFilters.h"

#define    kQCPlugIn_Name                @"OpenEmu Filters"
#define    kQCPlugIn_Description        @"Provides the scaling filters optimized for pixelated graphics from OpenEmu"


#pragma mark -
#pragma mark Static Functions




static void _TextureReleaseCallback(CGLContextObj cgl_ctx, GLuint name, void* info)
{
    glDeleteTextures(1, &name);
}

// our render setup
static GLuint renderToFBO(GLuint frameBuffer, CGLContextObj cgl_ctx, NSUInteger pixelsWide, NSUInteger pixelsHigh, NSRect bounds, GLuint videoTexture, v002Shader* shader)
{
	CGLLockContext(cgl_ctx);
	
	GLsizei							width = bounds.size.width,	height = bounds.size.height;
	GLuint							name;
	GLenum							status;
	
	// save our current GL state
	glPushAttrib(GL_COLOR_BUFFER_BIT | GL_TRANSFORM_BIT | GL_VIEWPORT);
	
	// Create texture to render into 
	glGenTextures(1, &name);
	glBindTexture(GL_TEXTURE_RECTANGLE_EXT, name);	
	glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL); 
	
	// bind our FBO
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, frameBuffer);
	
	// attach our just created texture
	glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_EXT, name, 0);
	
	// Assume FBOs JUST WORK, because we checked on startExecution	
	//	status = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);	
	//	if(status == GL_FRAMEBUFFER_COMPLETE_EXT)
	{	
		// Setup OpenGL states 
		glViewport(0, 0, width, height);
		glMatrixMode(GL_PROJECTION);
		glPushMatrix();
		glLoadIdentity();
		glOrtho(bounds.origin.x, bounds.origin.x + bounds.size.width, bounds.origin.y, bounds.origin.y + bounds.size.height, -1, 1);
		
		glMatrixMode(GL_MODELVIEW);
		glPushMatrix();
		glLoadIdentity();
		
        // bind video texture
		glClearColor(0.0, 0.0, 0.0, 0.0);
        glClear(GL_COLOR_BUFFER_BIT);        
        
        // draw our input video
        glEnable(GL_TEXTURE_RECTANGLE_EXT);
        glBindTexture(GL_TEXTURE_RECTANGLE_EXT, videoTexture);

        // force nearest neighbor filtering for our samplers to work in the shader...
        glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        
        glColor4f(1.0, 1.0, 1.0, 1.0);
        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

        // bind our shader
        glUseProgramObjectARB([shader programObject]);
        
        // set up shader variables
        glUniform1iARB([shader getUniformLocation:"OGL2Texture"], 0);    // texture        
    
        glBegin(GL_QUADS);    // Draw A Quad
        {
            glTexCoord2f(0.0f, 0.0f);
            glVertex2f(0.0f, 0.0f);        
            glTexCoord2f(pixelsWide, 0.0f );
            glVertex2f(width, 0.0f);
			glTexCoord2f(pixelsWide, pixelsHigh);
            glVertex2f(width, height);
            glTexCoord2f(0.0f, pixelsHigh);
            glVertex2f(0.0f, height);
        }
        glEnd(); // Done Drawing The Quad
        
		// disable shader program
		glUseProgramObjectARB(NULL);
		
		// Restore OpenGL states 
		glMatrixMode(GL_MODELVIEW);
		glPopMatrix();
		glMatrixMode(GL_PROJECTION);
		glPopMatrix();
		
		// restore states
		glPopAttrib();		
	}
	
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
	
	// Check for OpenGL errors 
	status = glGetError();
	if(status)
	{
		NSLog(@"OpenGL error %04X", status);
		glDeleteTextures(1, &name);
		name = 0;
	}
	
	CGLUnlockContext(cgl_ctx);
	return name;	
}



@implementation OpenEmuQCFiltersPlugin

/*
 Here you need to declare the input / output properties as dynamic as Quartz Composer will handle their implementation
 @dynamic inputFoo, outputBar;
 */

@dynamic inputImage, inputScaler, outputImage;

+ (NSDictionary*) attributes
{
    /*
     Return a dictionary of attributes describing the plug-in (QCPlugInAttributeNameKey, QCPlugInAttributeDescriptionKey...).
     */
    
    return [NSDictionary dictionaryWithObjectsAndKeys:kQCPlugIn_Name, QCPlugInAttributeNameKey, kQCPlugIn_Description, QCPlugInAttributeDescriptionKey, nil];
}

+ (NSDictionary*) attributesForPropertyPortWithKey:(NSString*)key
{
    if([key isEqualToString:@"inputImage"])
    {
        return [NSDictionary dictionaryWithObjectsAndKeys:@"Image", QCPortAttributeNameKey, nil];
    }
    
    if([key isEqualToString:@"inputScaler"])
    {
        return [NSDictionary dictionaryWithObjectsAndKeys:@"Scaler", QCPortAttributeNameKey,
                [NSArray arrayWithObjects:@"Scale2XPlus", @"Scale2XHQ", @"Scale4X", @"Scale4XHQ", nil], QCPortAttributeMenuItemsKey,
                [NSNumber numberWithUnsignedInteger:0.0], QCPortAttributeMinimumValueKey,
                [NSNumber numberWithUnsignedInteger:3], QCPortAttributeMaximumValueKey,
                [NSNumber numberWithUnsignedInteger:0], QCPortAttributeDefaultValueKey,
                nil];
    }
    
    if([key isEqualToString:@"outputImage"])
    {
        return [NSDictionary dictionaryWithObjectsAndKeys:@"Image", QCPortAttributeNameKey, nil];
    }
    return nil;
}

+ (NSArray*) sortedPropertyPortKeys
{
    return [NSArray arrayWithObjects:@"inputImage", @"inputAmount", nil];
}

+ (QCPlugInExecutionMode) executionMode
{
    /*
     Return the execution mode of the plug-in: kQCPlugInExecutionModeProvider, kQCPlugInExecutionModeProcessor, or kQCPlugInExecutionModeConsumer.
     */
    
    return kQCPlugInExecutionModeProcessor;
}

+ (QCPlugInTimeMode) timeMode
{
    /*
     Return the time dependency mode of the plug-in: kQCPlugInTimeModeNone, kQCPlugInTimeModeIdle or kQCPlugInTimeModeTimeBase.
     */
    
    return kQCPlugInTimeModeNone;
}

- (id) init
{
    if(self = [super init]) {
        /*
         Allocate any permanent resource required by the plug-in.
         */
    }
    
    return self;
}

- (void) finalize
{
    /*
     Release any non garbage collected resources created in -init.
     */
    
    [super finalize];
}

- (void) dealloc
{
    /*
     Release any resources created in -init.
     */
    [super dealloc];
}

@end

@implementation OpenEmuQCFiltersPlugin (Execution)

- (BOOL)startExecution:(id<QCPlugInContext>)context
{
    // work around lack of GLMacro.h for now
    CGLContextObj cgl_ctx = [context CGLContextObj];
    CGLLockContext(cgl_ctx);
		
	// WHY LOAD THE SHADERS FROM THE FUCKING OEFILTERS WHEN THE FUCKING SHADERS
	// ARE IN THE FUCKING QCPLUGINS RESOURCES FOLDER, LOCAL TO THE FUCKING
	// BUNDLE SO IF SOMONE COPIES IT THEY DONT BREAK EVERYRTHING????
	
	// ()!@*)(!@*# *pant*
	
	// build up and destroy an FBO. If it works, we are good to go and dont do any other slow error checking for our main rendering, 
    // if we cant make the FBO, fail by returning NO.
	
	// since we are using FBOs we ought to keep track of what was previously bound
	glGetIntegerv(GL_FRAMEBUFFER_BINDING_EXT, &previousFBO);	
	
    GLuint name;
    GLenum status;
    
    glGenTextures(1, &name);
    glBindTexture(GL_TEXTURE_RECTANGLE_EXT, name);
    glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGBA8, 640, 480, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    
    // Create temporary FBO to render in texture 
    glGenFramebuffersEXT(1, &frameBuffer);
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, frameBuffer);
    glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_EXT, name, 0);
    
    status = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
    if(status != GL_FRAMEBUFFER_COMPLETE_EXT)
    {    
        NSLog(@"Cannot create FBO");
		NSLog(@"OpenGL error %04X", status);

		glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, previousFBO);
        glDeleteFramebuffersEXT(1, &frameBuffer);
        glDeleteTextures(1, &name);
        CGLUnlockContext(cgl_ctx);
        return NO;
    }    
    
	// cleanup
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, previousFBO);
    glDeleteTextures(1, &name);
	
	// shaders
	NSBundle *pluginBundle =[NSBundle bundleForClass:[self class]];	
	
	Scale2xPlus = [[v002Shader alloc] initWithShadersInBundle:pluginBundle withName:@"Scale2XPlus" forContext:cgl_ctx];
	Scale2xHQ = [[v002Shader alloc] initWithShadersInBundle:pluginBundle withName:@"Scale2xHQ" forContext:cgl_ctx];
	Scale4x = [[v002Shader alloc] initWithShadersInBundle:pluginBundle withName:@"Scale4x" forContext:cgl_ctx];
	Scale4xHQ = [[v002Shader alloc] initWithShadersInBundle:pluginBundle withName:@"Scale4xHQ" forContext:cgl_ctx];
	
	/* 
	 Scale2xPlus = [[OEFilterPlugin gameShaderWithFilterName:@"Scale2xPlus" forContext:cgl_ctx] retain];
	 Scale2xHQ   = [[OEFilterPlugin gameShaderWithFilterName:@"Scale2xHQ"   forContext:cgl_ctx] retain];
	 Scale4x     = [[OEFilterPlugin gameShaderWithFilterName:@"Scale4x"     forContext:cgl_ctx] retain];
	 Scale4xHQ   = [[OEFilterPlugin gameShaderWithFilterName:@"Scale4xHQ"   forContext:cgl_ctx] retain];
	 */
	
    if((!Scale2xPlus) || (!Scale2xHQ) || (!Scale4x) || (!Scale4xHQ))
    {
        NSLog(@"could not init shaders");
        return NO;
    }
	
    CGLUnlockContext(cgl_ctx);
    
    return YES;
}

- (void) enableExecution:(id<QCPlugInContext>)context
{
	CGLContextObj cgl_ctx = [context CGLContextObj];
	CGLLockContext(cgl_ctx);
	
	// cache our previously bound fbo before every execution
	glGetIntegerv(GL_FRAMEBUFFER_BINDING_EXT, &previousFBO);
	CGLUnlockContext(cgl_ctx);
}

- (BOOL) execute:(id<QCPlugInContext>)context atTime:(NSTimeInterval)time withArguments:(NSDictionary*)arguments
{
    /*
     Called by Quartz Composer whenever the plug-in instance needs to execute.
     Only read from the plug-in inputs and produce a result (by writing to the plug-in outputs or rendering to the destination OpenGL context) within that method and nowhere else.
     Return NO in case of failure during the execution (this will prevent rendering of the current frame to complete).
     
     The OpenGL context for rendering can be accessed and defined for CGL macros using:
     CGLContextObj cgl_ctx = [context CGLContextObj];
     */
    
    CGLContextObj cgl_ctx = [context CGLContextObj];
    CGLLockContext(cgl_ctx);
    
    //NSLog(@"Quartz Composer: gl context when attempting to use shader: %p", cgl_ctx);
    
    id<QCPlugInInputImageSource>   image = self.inputImage;
    NSUInteger width = [image imageBounds].size.width;
    NSUInteger height = [image imageBounds].size.height;
    NSRect bounds;
    int multiplier;

    v002Shader* selectedShader;
    switch (self.inputScaler)
	{
        case 0:
		{
			selectedShader = Scale2xPlus;
			multiplier = 2.0;
			bounds = NSMakeRect(0.0, 0.0, width * multiplier, height * multiplier);
		}
        break;
        case 1:    
		{
			selectedShader = Scale2xHQ;
			multiplier = 2.0;
			bounds = NSMakeRect(0.0, 0.0, width * multiplier, height * multiplier);
		}
        break;
        case 2:    
        {
            selectedShader = Scale4x;
            multiplier = 4.0;
            bounds = NSMakeRect(0.0, 0.0, width * multiplier, height * multiplier);
        }
        break;
        case 3:    
        {
            selectedShader = Scale4xHQ;
            multiplier = 4.0;
            bounds = NSMakeRect(0.0, 0.0, width * multiplier, height * multiplier);
        }
        break;
    }
    
    if(image && [image lockTextureRepresentationWithColorSpace:[image imageColorSpace] forBounds:[image imageBounds]])
    {    
        [image bindTextureRepresentationToCGLContext:cgl_ctx textureUnit:GL_TEXTURE0 normalizeCoordinates:YES];
    
        // Make sure to flush as we use FBOs as the passed OpenGL context may not have a surface attached        
        GLuint finalOutput = renderToFBO(frameBuffer, cgl_ctx, width, height, bounds, [image textureName], selectedShader);
        glFlushRenderAPPLE();
        
        if(finalOutput == 0)
		{
			// exit cleanly
			[image unbindTextureRepresentationFromCGLContext:cgl_ctx textureUnit:GL_TEXTURE0];
            [image unlockTextureRepresentation];
			glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, previousFBO);
			CGLUnlockContext(cgl_ctx);
			return NO;
		}
	
#if __BIG_ENDIAN__
#define OEPlugInPixelFormat QCPlugInPixelFormatARGB8
#else
#define OEPlugInPixelFormat QCPlugInPixelFormatBGRA8
#endif
        // output our final image as a QCPluginOutputImageProvider using the QCPluginContext convinience method. No need to go through the trouble of making our own conforming object.    
        id provider = nil; // we are allowed to output nil.
		provider = [context outputImageProviderFromTextureWithPixelFormat:OEPlugInPixelFormat
                                                                  pixelsWide:width * multiplier
                                                                  pixelsHigh:height * multiplier
                                                                        name:finalOutput
                                                                     flipped:YES
                                                             releaseCallback:_TextureReleaseCallback
                                                              releaseContext:nil
                                                                  colorSpace:[image imageColorSpace]
                                                            shouldColorMatch:YES];
                
        self.outputImage = provider;
        
        [image unbindTextureRepresentationFromCGLContext:cgl_ctx textureUnit:GL_TEXTURE0];
        [image unlockTextureRepresentation];
    }    
    else
        self.outputImage = nil;

	// return to our previous FBO;
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, previousFBO);

    CGLUnlockContext(cgl_ctx);
    return YES;
}

- (void)disableExecution:(id<QCPlugInContext>)context
{
}

- (void)stopExecution:(id<QCPlugInContext>)context
{
    CGLContextObj cgl_ctx = [context CGLContextObj];
    // remove our GLSL program
    CGLLockContext(cgl_ctx);
    
    // release shaders
    [Scale2xPlus release];
    [Scale2xHQ release];
    [Scale4x release];
    [Scale4xHQ release];
    
    CGLUnlockContext(cgl_ctx);
}

@end