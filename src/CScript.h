#ifndef __CSCRIPT_H__
#define __CSCRIPT_H__

// Runs single SCM opcodes through the engine's own script interpreter, the way the PC
// SA-MP client does. Safer than writing to reverse engineered struct fields.
//
// Parameter format characters:
//   i  int        f  float (passed as double through varargs)
//   v  int* that receives a result
// Returns the condition result for conditional opcodes.
bool ScriptCommand(unsigned short opcode, const char* format, ...);

// Opcodes used by the client (GTA SA numbering)
#define OP_SET_CHAR_COORDINATES		0x00A1
#define OP_ADD_SCORE				0x0109
#define OP_STORE_SCORE				0x010B
#define OP_IS_CHAR_DEAD				0x0118
#define OP_SET_CHAR_HEADING			0x0173
#define OP_SET_PLAYER_CONTROL		0x01B4
#define OP_GET_PLAYER_CHAR			0x01F5
#define OP_SET_CHAR_HEALTH			0x0223
#define OP_REQUEST_MODEL			0x0247
#define OP_MARK_MODEL_NOT_NEEDED	0x0249
#define OP_RESTORE_CAMERA_JUMPCUT	0x02EB
#define OP_SET_CAMERA_BEHIND_PLAYER	0x0373
#define OP_LOAD_ALL_MODELS_NOW		0x038B
#define OP_SET_AREA_VISIBLE			0x04BB
#define OP_SET_CHAR_AREA_VISIBLE	0x0860
#define OP_SET_PLAYER_MODEL			0x09C7

#endif
