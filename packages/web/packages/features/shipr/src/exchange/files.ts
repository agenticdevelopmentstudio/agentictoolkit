/**
 * The two places a shipr document crosses between this page and the operator's disk.
 *
 * THE BROWSER PLUMBING ITSELF IS NOT HERE ANY MORE. `saveTextFile` and `readTextFile` are
 * `@agenticdevelopertoolkit/ui`'s `lib/file-exchange`: a `Blob`, an object URL, an `<a>` the DOM
 * has to click for us and a `File` turned into text have no opinion about what the bytes mean,
 * and integrations exports its provider configs through exactly the same three browser quirks.
 * What is left here is the one shipr-specific fact — that the bytes are a serialized
 * `ShiprDocument` and the file is called `DEFAULT_FILENAME`.
 */

import { readTextFile, saveTextFile } from '@agenticdevelopertoolkit/ui/lib/file-exchange';

import { DEFAULT_FILENAME, serializeDocument, type ShiprDocument } from './document';

export { readTextFile };

/**
 * Hand the operator the file, asking where it goes.
 *
 * NO SERVER ROUND TRIP. The document is built from the tree already on the screen, so a
 * download route would exist only to send bytes up and have them sent straight back — with a
 * second read of the fleet behind it that could disagree with what the operator is looking
 * at. What comes down is exactly what the console is showing.
 *
 * Resolves `false` when the operator dismissed the save dialog, so a caller can tell "saved"
 * from "changed their mind" rather than reporting both as done.
 */
export function downloadDocument(
  document: ShiprDocument,
  filename = DEFAULT_FILENAME,
): Promise<boolean> {
  return saveTextFile({
    text: serializeDocument(document),
    filename,
    description: 'shipr configuration',
  });
}
