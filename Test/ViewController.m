//
//  ViewController.m
//  Test
//
//  Created by Neil Wallace on 04/02/2014.
//  Copyright (c) 2014 Neil Wallace. All rights reserved.
//

#import "ViewController.h"
#include <vector>
#include <numeric>

#import "AppDelegate.h"

#define BUFFER_OFFSET(i) ((char *)NULL + (i))

// Uniform index.
enum
{
    UNIFORM_MODELVIEWPROJECTION_MATRIX,
    UNIFORM_NORMAL_MATRIX,
    UNIFORM_TEX_0_SAMPLER,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

#define PVR_TEXTURE_FLAG_TYPE_MASK	0xff
//static char gPVRTexIdentifier[5] = "PVR!";

enum
{
	kPVRTextureFlagTypePVRTC_2 = 24,
	kPVRTextureFlagTypePVRTC_4
};

typedef struct _PVRTexHeader
{
	uint32_t headerLength;
	uint32_t height;
	uint32_t width;
	uint32_t numMipmaps;
	uint32_t flags;
	uint32_t dataLength;
	uint32_t bpp;
	uint32_t bitmaskRed;
	uint32_t bitmaskGreen;
	uint32_t bitmaskBlue;
	uint32_t bitmaskAlpha;
	uint32_t pvrTag;
	uint32_t numSurfs;
} PVRTexHeader;

struct Vertex
{
    Vertex(float x, float y, float z, float uv_x, float uv_y, float r, float g, float b, float a)
    {
        tc[0] = uv_x;
        tc[1] = uv_y;
        pos[0] = x;
        pos[1] = y;
        pos[2] = z;
        colour[0] = r;
        colour[1] = g;
        colour[2] = b;
        colour[3] = a;
    }

    GLfloat pos[3];
    GLfloat tc[2];
    GLfloat colour[4];
};

std::vector<Vertex> verts;

@interface ViewController () {
    GLuint _program;
    
    GLKMatrix4 _modelViewProjectionMatrix;
    GLKMatrix3 _normalMatrix;
    
    GLuint _vertexArray;
    GLuint _vertexBuffer;
    
    GLKTextureInfo* glk_texture_info;
    
    GLuint _Width;
    GLuint _Height;
    NSMutableArray *_ImageData;
    GLuint _ID;
    GLenum _InternalFormat;
    bool _HasAlpha;
}
@property (strong, nonatomic) EAGLContext *context;
@property (strong, nonatomic) GLKBaseEffect *effect;

- (void)setupGL;
- (void)tearDownGL;

- (BOOL)loadShaders;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }
    
    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    
    [self setupGL];
}

- (void)dealloc
{
    [self tearDownGL];
    
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;
        
        [self tearDownGL];
        
        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }

    // Dispose of any resources that can be recreated.
}

void AddQuad(GLKVector3 pos, float size, GLKVector4 colour)
{
    verts.push_back(Vertex(pos.v[0]-size,  pos.v[1]-size,     pos.v[2],          0.0f,   1.0f, colour.v[0], colour.v[1], colour.v[2], colour.v[3]));
    verts.push_back(Vertex(pos.v[0]+size,  pos.v[1]-size,     pos.v[2],          1.0f,   1.0f, colour.v[0], colour.v[1], colour.v[2], colour.v[3]));
    verts.push_back(Vertex(pos.v[0]-size,  pos.v[1]+size,     pos.v[2],          0.0f,   0.0f, colour.v[0], colour.v[1], colour.v[2], colour.v[3]));
    verts.push_back(Vertex(pos.v[0]-size,  pos.v[1]+size,     pos.v[2],          0.0f,   0.0f, colour.v[0], colour.v[1], colour.v[2], colour.v[3]));
    verts.push_back(Vertex(pos.v[0]+size,  pos.v[1]-size,     pos.v[2],          1.0f,   1.0f, colour.v[0], colour.v[1], colour.v[2], colour.v[3]));
    verts.push_back(Vertex(pos.v[0]+size,  pos.v[1]+size,     pos.v[2],          1.0f,   0.0f, colour.v[0], colour.v[1], colour.v[2], colour.v[3]));
}

- (void)setupGL
{
	AddQuad({0,0,0}, 1.0f, {1,0,0,1});
    
    [EAGLContext setCurrentContext:self.context];
    
    [self loadShaders];
    
    glGenVertexArraysOES(1, &_vertexArray);
    glBindVertexArrayOES(_vertexArray);
    
    glGenBuffers(1, &_vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, verts.size() * sizeof(Vertex), verts.data(), GL_STATIC_DRAW);
    GLuint stride = sizeof(Vertex);
    
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, stride, BUFFER_OFFSET(0));
    glEnableVertexAttribArray(GLKVertexAttribTexCoord0);
    glVertexAttribPointer(GLKVertexAttribTexCoord0, 2, GL_FLOAT, GL_FALSE, stride, BUFFER_OFFSET(12));
    glEnableVertexAttribArray(GLKVertexAttribColor);
    glVertexAttribPointer(GLKVertexAttribColor, 4, GL_FLOAT, GL_FALSE, stride, BUFFER_OFFSET(20));
    
    glBindVertexArrayOES(0);
}

- (void)tearDownGL
{
    [EAGLContext setCurrentContext:self.context];
    
    glDeleteBuffers(1, &_vertexBuffer);
    glDeleteVertexArraysOES(1, &_vertexArray);
    
//    self.effect = nil;
    
    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update
{
    float aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
    GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(65.0f), aspect, 0.1f, 100.0f);
    
	double rotation = CACurrentMediaTime() * 0.2;
	
    static float scale = 8.0f;
    GLKMatrix4 modelViewMatrix = GLKMatrix4MakeScale(scale, scale, scale);
	modelViewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeRotation(rotation, 0, 0, 1), modelViewMatrix);
    modelViewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeTranslation(0.0f, 0.0f, -4.0f), modelViewMatrix);
    
    _normalMatrix = GLKMatrix3InvertAndTranspose(GLKMatrix4GetMatrix3(modelViewMatrix), NULL);
    
    _modelViewProjectionMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
	
	double start = CACurrentMediaTime();
	
	GLKMatrix4 x = GLKMatrix4MakeXRotation(0);
    GLKMatrix4 y = GLKMatrix4MakeYRotation(0);
    
    GLKMatrix4 spinmatrix = GLKMatrix4Multiply(x, y);
	GLKMatrix4 spinios = GLKMatrix4Scale(spinmatrix, 1, -1, 1);
	
	for(int i=0; i<15000; ++i)
	{
		float xpos, ypos;
		
		GLKMatrix3 m = GLKMatrix3MakeZRotation(M_PI);
		GLKVector3 pos = GLKVector3Make(0, 0, 1);
        pos = GLKMatrix3MultiplyVector3(m, pos);
		
		xpos = pos.v[0];
		ypos = pos.v[1];
		float zpos = 1;
		
		float cos_a = 1;
		float sin_a = 0;
		float scale = 1.0;
		
		float x1 = i;
		float x2 = i+1;
		float y1 = i;
		float y2 = i+1;
		
		GLKVector4 verts[4];
		
		verts[0].v[0] = xpos + ((x1*scale)*(float)cos_a)-((y1*scale)*(float)sin_a);
		verts[0].v[1] = ypos + ((x1*scale)*(float)sin_a)+((y1*scale)*(float)cos_a);
		verts[0].v[2] = zpos;
		verts[0].v[3] = 1.0f;
		verts[1].v[0] = xpos + ((x2*scale)*(float)cos_a)-((y1*scale)*(float)sin_a);
		verts[1].v[1] = ypos + ((x2*scale)*(float)sin_a)+((y1*scale)*(float)cos_a);
		verts[1].v[2] = zpos;
		verts[1].v[3] = 1.0f;
		verts[2].v[0] = xpos + ((x1*scale)*(float)cos_a)-((y2*scale)*(float)sin_a);
		verts[2].v[1] = ypos + ((x1*scale)*(float)sin_a)+((y2*scale)*(float)cos_a);
		verts[2].v[2] = zpos;
		verts[2].v[3] = 1.0f;
		verts[3].v[0] = xpos + ((x2*scale)*(float)cos_a)-((y2*scale)*(float)sin_a);
		verts[3].v[1] = ypos + ((x2*scale)*(float)sin_a)+((y2*scale)*(float)cos_a);
		verts[3].v[2] = zpos;
		verts[3].v[3] = 1.0f;
		
		GLKMatrix4MultiplyVector4Array(spinios, verts, 4);
	}
	
	double end = CACurrentMediaTime();
	
	double time = end-start;
	NSLog(@"Time = %1.3fms", time * 1000);
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
//    glBindVertexArrayOES(_vertexArray);
//
//	
//    glUseProgram(_program);
//    
//    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, _modelViewProjectionMatrix.m);
//    glUniformMatrix3fv(uniforms[UNIFORM_NORMAL_MATRIX], 1, 0, _normalMatrix.m);
//    
//    
//    glUniform1i(uniforms[UNIFORM_TEX_0_SAMPLER], 0);
//    
//    glDrawArrays(GL_TRIANGLES, 0, verts.size());
}

#pragma mark -  OpenGL ES 2 shader compilation

- (BOOL)loadShaders
{
    GLuint vertShader, fragShader;
    NSString *vertShaderPathname, *fragShaderPathname;
    
    // Create shader program.
    _program = glCreateProgram();
    
    // Create and compile vertex shader.
    vertShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"vsh"];
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER file:vertShaderPathname]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    // Create and compile fragment shader.
    fragShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"fsh"];
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragShaderPathname]) {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }
    
    // Attach vertex shader to program.
    glAttachShader(_program, vertShader);
    
    // Attach fragment shader to program.
    glAttachShader(_program, fragShader);
    
    // Bind attribute locations.
    // This needs to be done prior to linking.
    glBindAttribLocation(_program, GLKVertexAttribPosition, "position");
    glBindAttribLocation(_program, GLKVertexAttribNormal, "normal");
    glBindAttribLocation(_program, GLKVertexAttribColor, "colour");
    glBindAttribLocation(_program, GLKVertexAttribTexCoord0, "texCoord");
    
    // Link program.
    if (![self linkProgram:_program]) {
        NSLog(@"Failed to link program: %d", _program);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (_program) {
            glDeleteProgram(_program);
            _program = 0;
        }
        
        return NO;
    }
    
    // Get uniform locations.
    uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = glGetUniformLocation(_program, "modelViewProjectionMatrix");
    uniforms[UNIFORM_NORMAL_MATRIX] = glGetUniformLocation(_program, "normalMatrix");
    uniforms[UNIFORM_TEX_0_SAMPLER] = glGetUniformLocation(_program, "u_Tex0Sampler");
    
    // Release vertex and fragment shaders.
    if (vertShader) {
        glDetachShader(_program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(_program, fragShader);
        glDeleteShader(fragShader);
    }
    
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file
{
    GLint status;
    const GLchar *source;
    
    source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] UTF8String];
    if (!source) {
        NSLog(@"Failed to load vertex shader");
        return NO;
    }
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
    GLint logLength, status;
    
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

@end
