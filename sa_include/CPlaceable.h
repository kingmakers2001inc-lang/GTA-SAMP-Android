#ifndef __CPLACEABLE_H__
#define __CPLACEABLE_H__

struct Placement
{
	RwV3d pos;
	float angle;
};

class CMatrixLink;
class CPlaceable
{
public:
	Placement m_Placement;
	CMatrixLink* m_pMatrix;
	
	CPlaceable();
	virtual ~CPlaceable();
};

#if defined(__aarch64__)
// 2.11.311 (CPlaceable constructor, AllocateMatrix): vtable, placement at 0x08, matrix at 0x18
static_assert(__builtin_offsetof(CPlaceable, m_Placement) == 0x08, "CPlaceable layout");
static_assert(__builtin_offsetof(CPlaceable, m_pMatrix) == 0x18, "CPlaceable layout");
#endif

#endif