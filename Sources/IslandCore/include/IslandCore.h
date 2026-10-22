#ifndef ISLAND_CORE_H
#define ISLAND_CORE_H
#include <stdint.h>
typedef struct Island Island;
typedef struct { uint32_t expanded; uint32_t pinned; uint32_t visible; uint64_t deadline_ms; } IslandSnapshot;
Island *island_create(void);
IslandSnapshot island_event(Island *island, uint32_t event, uint64_t now_ms);
void island_destroy(Island *island);
#endif
