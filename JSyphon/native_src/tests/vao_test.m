#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl3.h>
#import <Syphon/Syphon.h>

int main(void) {
    @autoreleasepool {
        CGLContextObj ctx = NULL;
        CGLPixelFormatAttribute attrs[] = {
            kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core,
            kCGLPFAColorSize, 24, kCGLPFAAlphaSize, 8,
            kCGLPFADoubleBuffer, (CGLPixelFormatAttribute)0 };
        CGLPixelFormatObj pf; GLint npix;
        if (CGLChoosePixelFormat(attrs, &pf, &npix)) { fprintf(stderr, "pf failed\n"); return 2; }
        CGLCreateContext(pf, NULL, &ctx);
        CGLSetCurrentContext(ctx);
        printf("GL version: %s\n", glGetString(GL_VERSION));

        GLuint vao = 0; glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        GLint bound = -1; glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &bound);
        printf("caller VAO bound before publish: %d (expect %u)\n", bound, vao);

        GLuint tex = 0; glGenTextures(1, &tex);
        glBindTexture(GL_TEXTURE_2D, tex);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 640, 480, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);

        SyphonServer *s = [[SyphonServer alloc] initWithName:@"VaoTest" context:ctx options:nil];
        printf("server=%p\n", s);

        [s publishFrameTexture:tex textureTarget:GL_TEXTURE_2D
                   imageRegion:NSMakeRect(0, 0, 640, 480)
             textureDimensions:NSMakeSize(640, 480) flipped:NO];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];

        glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &bound);
        GLenum e = glGetError();
        printf("caller VAO bound after publish: %d (expect %u)  glError=0x%x\n", bound, vao, e);
        return (bound == (GLint)vao && e == GL_NO_ERROR) ? 0 : 1;
    }
}
