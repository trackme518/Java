#import <jni.h>
#import <JavaNativeFoundation/JavaNativeFoundation.h>	// JNI Cocoa helper

#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#import <Syphon/Syphon.h>

#import <OpenGL/CGLMacro.h>

#ifndef GL_TEXTURE_BINDING_RECTANGLE
#define GL_TEXTURE_BINDING_RECTANGLE 0x84F6
#endif
#ifndef GL_TEXTURE_RECTANGLE
#define GL_TEXTURE_RECTANGLE 0x84F5
#endif
#ifndef GL_VERTEX_ARRAY_BINDING
#define GL_VERTEX_ARRAY_BINDING 0x85B5
#endif
#ifndef GL_VERSION_3_0
extern void glBindVertexArray(GLuint array);
#endif

// The Syphon server draws through its own (share-group) context. On Apple's
// GL-over-Metal implementation some per-context state is shared between
// contexts in a share group, so the publish can clobber state the calling
// (Processing) context relies on. Capture the state Syphon may touch and put
// it back after each call that draws.
#define JSYPHON_TEXTURE_UNITS 4

typedef struct {
    GLint activeTexture;
    GLint texture2D[JSYPHON_TEXTURE_UNITS];
    GLint textureRectangle[JSYPHON_TEXTURE_UNITS];
    GLint vertexArray;
    GLint renderBuffer;
    GLint readFramebuffer;
    GLint drawFramebuffer;
    GLint arrayBuffer;
    GLint elementArrayBuffer;
    GLint viewport[4];
    GLint scissorBox[4];
    GLboolean scissorTest;
    GLboolean blend;
    GLint program;
} JNSyphonGLState;

static void jsyphon_gl_state_save(JNSyphonGLState *state)
{
    CGLContextObj cgl_ctx = CGLGetCurrentContext();
    glGetIntegerv(GL_ACTIVE_TEXTURE, &state->activeTexture);
    for (GLint unit = 0; unit < JSYPHON_TEXTURE_UNITS; unit++) {
        glActiveTexture(GL_TEXTURE0 + unit);
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &state->texture2D[unit]);
        glGetIntegerv(GL_TEXTURE_BINDING_RECTANGLE, &state->textureRectangle[unit]);
    }
    glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &state->vertexArray);
    glGetIntegerv(GL_RENDERBUFFER_BINDING, &state->renderBuffer);
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &state->readFramebuffer);
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &state->drawFramebuffer);
    glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &state->arrayBuffer);
    glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, &state->elementArrayBuffer);
    glGetIntegerv(GL_VIEWPORT, state->viewport);
    glGetIntegerv(GL_SCISSOR_BOX, state->scissorBox);
    glGetBooleanv(GL_SCISSOR_TEST, &state->scissorTest);
    glGetBooleanv(GL_BLEND, &state->blend);
    glGetIntegerv(GL_CURRENT_PROGRAM, &state->program);
}

static void jsyphon_gl_state_restore(JNSyphonGLState *state)
{
    CGLContextObj cgl_ctx = CGLGetCurrentContext();
    glUseProgram(state->program);
    glViewport(state->viewport[0], state->viewport[1], state->viewport[2], state->viewport[3]);
    glScissor(state->scissorBox[0], state->scissorBox[1], state->scissorBox[2], state->scissorBox[3]);
    if (state->scissorTest) {
        glEnable(GL_SCISSOR_TEST);
    } else {
        glDisable(GL_SCISSOR_TEST);
    }
    if (state->blend) {
        glEnable(GL_BLEND);
    } else {
        glDisable(GL_BLEND);
    }
    glBindRenderbuffer(GL_RENDERBUFFER, state->renderBuffer);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, state->readFramebuffer);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, state->drawFramebuffer);
    // Rebind the VAO before the buffer bindings: element array binding lives in the VAO
    glBindVertexArray(state->vertexArray);
    glBindBuffer(GL_ARRAY_BUFFER, state->arrayBuffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, state->elementArrayBuffer);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, state->texture2D[0]);
    glBindTexture(GL_TEXTURE_RECTANGLE, state->textureRectangle[0]);
    for (GLint unit = 1; unit < JSYPHON_TEXTURE_UNITS; unit++) {
        glActiveTexture(GL_TEXTURE0 + unit);
        glBindTexture(GL_TEXTURE_2D, state->texture2D[unit]);
        glBindTexture(GL_TEXTURE_RECTANGLE, state->textureRectangle[unit]);
    }
    glActiveTexture(state->activeTexture);
}

JNIEXPORT jlong JNICALL Java_jsyphon_JSyphonServer_initWithName (JNIEnv * env, jobject jobj, jstring name, jobject options)
{
    jlong ptr = 0;
    
	JNF_COCOA_ENTER(env);
    
    CGLContextObj cgl_ctx = CGLGetCurrentContext();
    
    NSString* sname = JNFJavaToNSString(env, name);

    NSDictionary* sopt = nil;
    if (options != nil) {
        JNFTypeCoercer* coecer = [JNFDefaultCoercions defaultCoercer];
        [JNFDefaultCoercions addMapCoercionTo:coecer];
        sopt = [coecer coerceJavaObject:options withEnv:env];
    }
    
	SyphonServer* server = [[SyphonServer alloc] initWithName:sname context:cgl_ctx options:nil];
    ptr = ptr_to_jlong(server);
    
	JNF_COCOA_EXIT(env);

	return ptr;
}

JNIEXPORT jstring JNICALL Java_jsyphon_JSyphonServer_getName (JNIEnv * env, jobject jobj, jlong ptr)
{
	jstring name = NULL;
	
	JNF_COCOA_ENTER(env);
    
    SyphonServer* server = jlong_to_ptr(ptr);
	name = JNFNSToJavaString(env, [server name]);
	
	JNF_COCOA_EXIT(env);
	
	return name;
}

JNIEXPORT jboolean JNICALL Java_jsyphon_JSyphonServer_hasClients(JNIEnv * env, jobject jobj, jlong ptr)
{
    jboolean hasClients = JNI_FALSE;
    BOOL tf = NO;
    
    JNF_COCOA_ENTER(env);
    SyphonServer* server = jlong_to_ptr(ptr);
    tf = [server hasClients];
    
    JNF_COCOA_EXIT(env);
    
    if(tf)
        hasClients = JNI_TRUE;
    
    return hasClients;
}

JNIEXPORT void JNICALL Java_jsyphon_JSyphonServer_publishFrameTexture(JNIEnv * env, jobject jobj, jlong ptr, jint texID, jint texTarget, jint xPos, jint yPos, jint width, jint height, jint sizeX, jint sizeY, jboolean isFlipped)
{
	JNF_COCOA_ENTER(env);
	
	// Put Code Here
	NSRect rect = NSMakeRect(xPos, yPos, width, height);
	NSSize size = NSMakeSize(sizeX, sizeY);
	
	GLuint textureID = texID ;
	GLuint textureTarget = texTarget;
    SyphonServer* server = jlong_to_ptr(ptr);

    JNSyphonGLState state;
    jsyphon_gl_state_save(&state);
    [server publishFrameTexture:textureID textureTarget:textureTarget imageRegion:rect textureDimensions:size flipped:(isFlipped == JNI_TRUE)];
    jsyphon_gl_state_restore(&state);

	JNF_COCOA_EXIT(env);
}

JNIEXPORT jboolean JNICALL Java_jsyphon_JSyphonServer_bindToDrawFrameOfSize(JNIEnv * env, jobject jobj, jlong ptr, jint sizeX, jint sizeY)
{
    jboolean jbool = JNI_FALSE;
    BOOL tf = NO;
    
	JNF_COCOA_ENTER(env);
	
	NSSize size = NSMakeSize(sizeX, sizeY);
	
    SyphonServer* server = jlong_to_ptr(ptr);
	tf = [server bindToDrawFrameOfSize:size];
	
	JNF_COCOA_EXIT(env);
    
    if(tf)
        jbool = JNI_TRUE;
    
    return jbool;
}

JNIEXPORT void JNICALL Java_jsyphon_JSyphonServer_unbindAndPublish(JNIEnv * env, jobject jobj, jlong ptr)
{
	JNF_COCOA_ENTER(env);
    
    SyphonServer* server = jlong_to_ptr(ptr);
	[server unbindAndPublish];
	
	JNF_COCOA_EXIT(env);
}

JNIEXPORT void JNICALL Java_jsyphon_JSyphonServer_stop(JNIEnv * env, jobject jobj, jlong ptr)
{
	JNF_COCOA_ENTER(env);	
	
    SyphonServer* server = jlong_to_ptr(ptr);
	[server stop];
	
	JNF_COCOA_EXIT(env);
}