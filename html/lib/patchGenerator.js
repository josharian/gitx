// Patch generation logic for partial line staging/unstaging
// Used by commit.js in browser and by tests in Node.js

(function(exports) {
    /**
     * Generate a partial patch for selected lines within a hunk.
     *
     * @param {Object} options
     * @param {string[]} options.lines - Array of diff lines (context, del, add) without hunk header
     * @param {Object} options.selectedIndices - Map of line index -> true for selected lines
     * @param {Object} options.delToAddPair - Map of del line index -> paired add line index
     * @param {boolean} options.reverse - True for unstaging, false for staging
     * @param {number} [options.baseIndex=1] - Base index for first line (default 1)
     * @returns {Object} { content: string, oldCount: number, newCount: number }
     */
    function generatePatchContent(options) {
        var lines = options.lines;
        var selectedIndices = options.selectedIndices;
        var delToAddPair = options.delToAddPair;
        var reverse = options.reverse;
        var baseIndex = options.baseIndex !== undefined ? options.baseIndex : 1;

        // Build index->line mapping
        var lineByIndex = {};
        for (var i = 0; i < lines.length; i++) {
            lineByIndex[baseIndex + i] = lines[i];
        }

        // Build patch. For paired del/add changes, we need them together at the right position:
        // - For staging: output at del position (matches working tree)
        // - For unstaging (reverse): output at add position (matches index)
        var patch = "";
        var count = [0, 0];
        var deferredDels = {};  // For reverse: addIdx -> del line text
        var usedAddIndices = {};  // For !reverse: track adds already output with their del

        for (var i = 0; i < lines.length; i++) {
            var l = lines[i];
            var firstChar = l.charAt(0);
            var lineIndex = baseIndex + i;

            var isSelected = selectedIndices[lineIndex];

            if (firstChar == '-') {
                // Deletion line
                if (isSelected) {
                    var pairedAddIdx = delToAddPair[lineIndex];
                    if (pairedAddIdx !== undefined && reverse) {
                        // For reverse: defer del until we reach paired add (to match index order)
                        deferredDels[pairedAddIdx] = l;
                    } else if (pairedAddIdx !== undefined && !reverse) {
                        // For staging: output del now, then paired add immediately (to match worktree order)
                        patch += l + "\n";
                        count[0]++;
                        if (lineByIndex[pairedAddIdx]) {
                            patch += lineByIndex[pairedAddIdx] + "\n";
                            count[1]++;
                            usedAddIndices[pairedAddIdx] = true;
                        }
                    } else {
                        // Unpaired del - output now
                        patch += l + "\n";
                        count[0]++;
                    }
                } else {
                    // Convert to context for staging (or skip for unstaging)
                    if (!reverse) {
                        patch += ' ' + l.substr(1) + "\n";
                        count[0]++; count[1]++;
                    }
                    // For reverse (unstaging), unselected del lines are skipped
                }
            } else if (firstChar == '+') {
                // For reverse: check if there's a deferred del to output first
                if (deferredDels[lineIndex]) {
                    patch += deferredDels[lineIndex] + "\n";
                    count[0]++;
                    delete deferredDels[lineIndex];
                }

                // Skip if already output as part of a pair (staging mode)
                if (usedAddIndices[lineIndex]) continue;

                // Addition line
                if (isSelected) {
                    patch += l + "\n";
                    count[1]++;
                } else {
                    // Convert to context for unstaging (or skip for staging)
                    if (reverse) {
                        patch += ' ' + l.substr(1) + "\n";
                        count[0]++; count[1]++;
                    }
                    // For staging, unselected add lines are skipped
                }
            } else {
                // Context line
                patch += l + "\n";
                count[0]++; count[1]++;
            }
        }

        return {
            content: patch,
            oldCount: count[0],
            newCount: count[1]
        };
    }

    exports.generatePatchContent = generatePatchContent;

})(typeof module !== 'undefined' && module.exports ? module.exports : (window.PatchGenerator = {}));
