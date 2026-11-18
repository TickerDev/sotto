# Requested document reading

Sotto can read explicitly requested local PDF, TXT, Markdown, RTF and DOCX documents for summarization. Use a literal document path, an explicitly named approved file alias, or a supported result from an actual search. The runtime enforces this scope; a model-generated path alone cannot authorize a read. Searching or showing a file does not read its contents automatically.

## Scanned PDF fallback

Embedded PDF text is preferred. If a page has no non-whitespace embedded text, Sotto renders that page in memory and runs Apple Vision text recognition locally. Neither the raster nor the recognition request is sent to a separate OCR service. OCR needs no new account, download prompt or screen-capture permission, and runs only as part of the requested read.

| Bound | Limit |
| --- | --- |
| File input | 20 MB |
| PDF pages inspected | First 50 |
| OCR pages attempted | First 5 textless pages within that range |
| OCR raster | At most 2,000 pixels on each edge, preserving the page aspect ratio/rotation |
| Extracted output | 16,000 characters total, in page order |
| Apple reasoning projection | Existing 2,500-character excerpt, explicitly marked partial |

Each OCR image is at most four million pixels. These are data/work bounds, not a wall-clock latency guarantee; native parsing and recognition can take time. The read checks cancellation between stages and cancels an in-flight Vision request. A canceled read does not return partial document content for execution or summarization.

If the OCR page budget is exhausted, later textless pages are skipped while later embedded-text pages can still be read. A skipped or failed page, the PDF page cap, or the text cap marks the result partial. Page metadata uses one-based indices: `ocr_pages_attempted`, `ocr_pages_with_text`, `ocr_skipped_pages`, and `unreadable_pages`. `pages_inspected` counts examined pages, including skipped/unreadable ones; it is not a guarantee of successful extraction from every page.

No recognized text means an honest unavailable result. Empty/illegible scans are not filled in with guessed content. Password-locked, invalid, oversized and unsupported files retain explicit errors.

## Accuracy, privacy and summaries

OCR can misread spelling, numbers and layout. Tables, columns, handwriting and poor scans may produce incomplete or incorrect text. Pages already containing embedded text do not receive OCR, so image-only regions on those pages can be omitted. OCR use and partial extraction must be disclosed in the summary; no full-document coverage is claimed for a bounded excerpt.

Extracted text, including OCR text, is untrusted document data. Instructions inside a document cannot grant permission, expand tool capabilities or authorize another read. Tool descriptions and runtime instructions retain that boundary.

Extraction and OCR happen locally, but the selected reasoning provider receives the extracted text under its existing processing choice/consent to produce a summary. This is the same destination policy as ordinary text extraction. Activity history stores the read summary, filename and extraction status, not the document body or rendered images. There is no background OCR. Automatic local indexing uses bounded excerpts from accessible PDF, TXT/Markdown, RTF and DOCX files; those excerpts stay local and respect exclusions and scope revocation.

Legacy DOC, macro-enabled DOCM, Pages, RTFD packages and arbitrary image files are not document-reading inputs. Opening those files in their own applications is a separate capability. Full-document chunking/summarization remains future work.

## Word, rich text and Unicode text

TXT/Markdown accept UTF-8 (with or without a BOM) and explicitly BOM-marked UTF-16 little/big endian. The reader rejects odd code-unit counts, invalid round trips, NUL-containing binary content and unsupported encodings instead of guessing a legacy encoding.

RTF uses the native attributed-string importer on at most 2 MB of input. Formatting is not preserved. Documents containing fields (including field-based hyperlinks), pictures, file tables, binary data or embedded objects are refused; export a PDF or text copy for those documents. The importer receives in-memory data rather than a URL.

DOCX extraction reads only [Content_Types].xml and word/document.xml in memory. It never unpacks an archive to disk, reads relationship targets, opens linked URLs or executes embedded content. Main-body paragraph/table text is retained; headers, footers, comments, deleted/explicitly hidden runs, images and embedded objects are omitted. Style-inherited visibility and page layout are not resolved. Pagination is unavailable for Word/RTF extraction; summaries must disclose the text-only coverage.

Word archives are limited to 20 MB compressed input, 512 entries, 8 MB expanded per selected entry and a maximum 200:1 selected-entry compression ratio. Only stored/raw-deflate entries are supported. Split, encrypted, ZIP64, duplicate selected entries, inconsistent local/central headers and failed CRC checks are refused. XML type metadata is capped at 512 KB. DTD/entity declarations are refused, external entity resolution is disabled, XML nesting is capped at 128 levels and text output remains bounded to 16,000 characters. Macro-enabled main-document types are rejected even when renamed .docx.

Automatic content indexing reuses these readers with an 8,000-character excerpt and its existing 2 MB file limit. No extra folder-selection/build step is required. Corrupt/unsupported documents are skipped rather than producing invented searchable text. Search results expose references, not cached document bodies.

Document content is untrusted. After a requested document read, subsequent tool calls require approval—including network searches that could disclose document text. The same rule applies to follow-up turns containing document tool context; a document cannot silently authorize another action.

## Implementation evidence

Automated fixtures create PDFs with actual raster-only text and verify that PDFKit finds no embedded text before the real Apple Vision path extracts it. Other checks cover embedded-text preference, mixed-page order and OCR caps, failed-page partial results, cancellation discarding earlier text, character limits and rotated raster dimensions. No personal document or account is used. See [VALIDATION.md](VALIDATION.md) for the recorded results; manual acceptance remains paused.

API references: Apple's [Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest) and [PDF drawing transforms](https://developer.apple.com/documentation/coregraphics/cgpdfpage/getdrawingtransform(_:rect:rotate:preserveaspectratio:)).
