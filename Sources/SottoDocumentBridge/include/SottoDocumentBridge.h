#ifndef SOTTO_DOCUMENT_BRIDGE_H
#define SOTTO_DOCUMENT_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
/* Bounded, raw ZIP deflate only. Requires exact input consumption and output size. */
int sotto_document_inflate(const uint8_t *input, size_t input_count, uint8_t *output, size_t output_count);
uint32_t sotto_document_crc32(const uint8_t *bytes, size_t count);
#endif
