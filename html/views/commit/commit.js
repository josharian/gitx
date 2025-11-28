/* Commit: Interface for selecting, staging, discarding, and unstaging
   hunks, individual lines, or ranges of lines.  */

var contextLines = 0;
var currentCommitSelection = null;
var pendingScrollY = null;

// Cross-browser scroll helpers
var getScrollY = function() {
	return window.pageYOffset || document.documentElement.scrollTop || document.body.scrollTop || 0;
};
var setScrollY = function(y) {
	window.scrollTo(0, y);
};

var showNewFile = function(file, diffContents, options)
{
	options = options || {};
	var path = "";
	if (file && file.path)
		path = file.path.toString();
	setTitle("New file: " + path.escapeHTML());

	if (diffContents == null) {
		notify("Can not display changes (Binary file?)", -1);
		diff.innerHTML = "";
		return;
	}

	var contents = diffContents.toString();
	var notice = "";
	if (options.diffWasTruncated) {
		var limit = typeof options.truncateLimit === "number" && options.truncateLimit > 0 ? options.truncateLimit : 1024;
		notice = '<div class="truncation-notice">Diff truncated to ' + limit + " characters for preview.</div>";
	}
	diff.innerHTML = "<pre>" + contents.escapeHTML() + "</pre>" + notice;
	diff.style.display = '';
}

var hideState = function() {
	document.getElementById("state").style.display = "none";
}

var setState = function(state) {
	setTitle(state);
	hideNotification();
	document.getElementById("state").style.display = "";
	document.getElementById("diff").style.display = "none";
	document.getElementById("state").innerHTML = state.escapeHTML();
}

var setTitle = function(status) {
	document.getElementById("status").innerHTML = status;
	document.getElementById("contextSize").style.display = "none";
	document.getElementById("contextTitle").style.display = "none";
}

var displayContext = function() {
	document.getElementById("contextSize").style.display = "";
	document.getElementById("contextTitle").style.display = "";
	contextLines = document.getElementById("contextSize").value;
}

var showFileChanges = function(file, cached, options) {
	options = options || {};
	if (!file || !file.path) {
		setState("No file selected");
		return;
	}

	hideNotification();
	hideState();

	var diffData = typeof options.diff === "string" ? options.diff : "";
	var isBinary = options.isBinary === true;
	var diffWasTruncated = options.diffWasTruncated === true;
	var truncateLimit = typeof options.truncateLimit === "number" && options.truncateLimit > 0 ? options.truncateLimit : null;
	if (typeof options.contextLines !== "undefined") {
		contextLines = parseInt(options.contextLines, 10) || 0;
	}

	var slider = document.getElementById("contextSize");
	if (slider) {
		slider.oninput = function() {
			contextLines = parseInt(slider.value, 10) || 0;
			requestCommitDiff();
		};
		if (typeof options.contextLines !== "undefined")
			slider.value = options.contextLines;
		else
			contextLines = parseInt(slider.value, 10) || 0;
	}

	if (file.status == 0) {
		if (isBinary)
			return showNewFile(file, null, { diffWasTruncated: diffWasTruncated, truncateLimit: truncateLimit });
		return showNewFile(file, diffData, { diffWasTruncated: diffWasTruncated, truncateLimit: truncateLimit });
	}

	var path = file.path.toString();
	setTitle((cached ? "Staged": "Unstaged") + " changes for " + path.escapeHTML());
	displayContext();

	if (isBinary) {
		notify("Can not display changes (Binary file?)", -1);
		document.getElementById("diff").innerHTML = "";
		return;
	}

	if (!diffData.length) {
		notify("This file has no more changes", 1);
		return;
	}

	displayDiff(diffData, cached, { diffWasTruncated: diffWasTruncated, truncateLimit: truncateLimit });
}

var requestCommitDiff = function () {
	if (!currentCommitSelection || !currentCommitSelection.file)
		return;

	gitxBridge.post("requestCommitDiff", {
		path: currentCommitSelection.path || "",
		cached: !!currentCommitSelection.cached,
		contextLines: contextLines
	});
};

var handleCommitSelectionChanged = function (message) {
	var fileData = null;
	if (message && typeof message.file === "object")
		fileData = message.file;

	var pathString = "";
	if (fileData && typeof fileData.path !== "undefined" && fileData.path !== null)
		pathString = fileData.path.toString();

	var cached = !!(message && message.cached);

	// If same file and same staged/unstaged state, skip the refresh
	// This preserves scroll position when index updates trigger spurious selection changes
	if (currentCommitSelection &&
		currentCommitSelection.path === pathString &&
		currentCommitSelection.cached === cached) {
		return;
	}

	currentCommitSelection = null;

	var diffElement = document.getElementById("diff");
	if (diffElement) {
		diffElement.innerHTML = "";
	}

	hideNotification();
	hideState();

	if (!fileData || typeof fileData.path === "undefined") {
		setState("No file selected");
		return;
	}

	currentCommitSelection = {
		file: fileData,
		cached: cached,
		path: pathString
	};

	var slider = document.getElementById("contextSize");
	if (slider)
		contextLines = parseInt(slider.value, 10) || 0;

	requestCommitDiff();
};

var findParentElementByTag = function (el, tagName)
{
	tagName = tagName.toUpperCase();
	while (el && el.tagName != tagName && el.parentNode) {
		el = el.parentNode;
	}
	return el;
}

// Find the diff-row or hunkheader parent element
var findDiffRow = function(el) {
	while (el && el.parentNode) {
		if (el.classList && (el.classList.contains('diff-row') || el.classList.contains('hunkheader'))) {
			return el;
		}
		el = el.parentNode;
	}
	return null;
}

/* Set the event handlers for mouse clicks/drags */
var setSelectHandlers = function()
{
	document.onmousedown = function(event) {
		if(event.which != 1) return false;
		deselect();
		currentSelection = false;
	}
	document.onselectstart = function () {return false;}; /* prevent normal text selection */

	var list = document.getElementsByClassName("lines");

	document.onmouseup = function(event) {
		// Handle button releases outside of lines list
		for (i = 0; i < list.length; ++i) {
			file = list[i];
			file.onmouseover = null;
			file.onmouseup = null;
		}
	}

	for (i = 0; i < list.length; ++i) {
		var file = list[i];
		file.ondblclick = function (event) {
			var target = findDiffRow(event.target);
			if (!target) return false;

			var file = target.parentNode;
			if (file.id == "selected")
				file = file.parentNode;

			// Check if it's a row that can be selected for sub-hunk
			var rowClass = target.getAttribute("class") || "";
			if (rowClass.indexOf("delline") >= 0 || rowClass.indexOf("addline") >= 0 || rowClass.indexOf("changeline") >= 0) {
				deselect();
				var bounds = findsubhunk(target);
				showSelection(file, bounds[0], bounds[1], true);
			}
			return false;
		};

		file.onmousedown = function(event) {
			if (event.which != 1)
				return false;
			var elem_class = event.target.getAttribute("class") || "";
			event.stopPropagation();
			if (elem_class.indexOf("hunkheader") >= 0 || elem_class.indexOf("hunkbutton") >= 0)
				return false;

			var target = findDiffRow(event.target);
			if (!target) return false;

			var file = target.parentNode;
			if (file.id && file.id == "selected")
				file = file.parentNode;

			file.onmouseup = function(event) {
				file.onmouseover = null;
				file.onmouseup = null;
				event.stopPropagation();
				return false;
			};

			if (event.shiftKey && currentSelection) { // Extend selection
				var index = parseInt(target.getAttribute("index"));
				var min = parseInt(currentSelection.bounds[0].getAttribute("index"));
				var max = parseInt(currentSelection.bounds[1].getAttribute("index"));
				var ender = 1;
				if(min > max) {
					var tmp = min; min = max; max = tmp;
					ender = 0;
				}

				if (index < min)
					showSelection(file,currentSelection.bounds[ender],target);
				else if (index > max)
					showSelection(file,currentSelection.bounds[1-ender],target);
				else
					showSelection(file,currentSelection.bounds[0],target);
				return false;
			}

			var srcElement = findDiffRow(event.srcElement);
			if (!srcElement) return false;

			file.onmouseover = function(event2) {
				var target2 = findDiffRow(event2.target);
				if (target2) {
					showSelection(file, srcElement, target2);
				}
				return false;
			};
			showSelection(file, srcElement, srcElement);
			return false;
		}
	}
}

var diffHeader;
var originalDiff;
var originalCached;

var displayDiff = function(diff, cached, options)
{
	options = options || {};
	var diffWasTruncated = options.diffWasTruncated === true;
	var truncateLimit = typeof options.truncateLimit === "number" && options.truncateLimit > 0 ? options.truncateLimit : 1024;
	diffHeader = diff.split("\n").slice(0,4).join("\n");
	originalDiff = diff;
	originalCached = cached;

	var diffElement = document.getElementById("diff");
	diffElement.style.display = "";
	highlightDiff(diff, diffElement);
	hunkHeaders = diffElement.getElementsByClassName("hunkheader");

	for (i = 0; i < hunkHeaders.length; ++i) {
		var header = hunkHeaders[i];
		if (cached)
			header.innerHTML = "<a href='#' class='hunkbutton' onclick='addHunk(this, true); return false'>Unstage</a>" + header.innerHTML;
		else {
			header.innerHTML = "<a href='#' class='hunkbutton' onclick='addHunk(this, false); return false'>Stage</a>" + header.innerHTML;
			header.innerHTML = "<a href='#' class='hunkbutton' onclick='discardHunk(this, event); return false'>Discard</a>" + header.innerHTML;
		}
	}
	setSelectHandlers();
	if (diffWasTruncated && diffElement) {
		var notice = document.createElement("div");
		notice.setAttribute("class", "truncation-notice");
		notice.textContent = "Diff truncated to " + truncateLimit + " characters for preview.";
		diffElement.appendChild(notice);
	}
	// Restore scroll position if we're refreshing after a hunk operation
	if (pendingScrollY !== null) {
		var scrollToRestore = pendingScrollY;
		pendingScrollY = null;
		setTimeout(function() { setScrollY(scrollToRestore); }, 0);
	}
}

var getNextText = function(element)
{
	// gets the next DOM sibling which has type "text" (e.g. our hunk-header)
	next = element;
	while (next.nodeType != 3) {
		next = next.nextSibling;
	}
	return next;
}


/* Get the original hunk lines attached to the given hunk header */
var getLines = function (hunkHeader)
{
	var start = originalDiff.indexOf(hunkHeader);
	var end = originalDiff.indexOf("\n@@", start + 1);
	var end2 = originalDiff.indexOf("\ndiff", start + 1);
	if (end2 < end && end2 > 0)
		end = end2;
	if (end == -1)
		end = originalDiff.length;
	return originalDiff.substring(start, end)+'\n';
}

/* Get the full hunk test, including diff top header */
var getFullHunk = function(hunk)
{
	hunk = getNextText(hunk);
	var hunkHeader = hunk.data.split("\n")[0];
	var m;
	if (m = hunkHeader.match(/@@.*@@/))
		hunkHeader = m;
	return diffHeader + "\n" + getLines(hunkHeader);
}

var addHunkText = function(hunkText, reverse)
{
	if (!hunkText)
		return;

	gitxBridge.post("commitApplyPatch", {
		patch: hunkText,
		reverse: !!reverse,
		stage: true
	});
}

/* Add the hunk located below the current element */
var addHunk = function(hunk, reverse)
{
	pendingScrollY = getScrollY();
	addHunkText(getFullHunk(hunk), reverse);
}

var discardHunk = function(hunk, event)
{
	var hunkText = getFullHunk(hunk);
	var altPressed = event && event.altKey === true;

	pendingScrollY = getScrollY();
	gitxBridge.post("commitDiscardHunk", {
		patch: hunkText,
		altKey: altPressed
	});
}

// Extract just the @@ line from hunk header text (strips button text)
var extractHunkHeaderLine = function(text) {
	var match = text.match(/@@[^@]+@@/);
	return match ? match[0] : null;
};

/* Split a hunk at the selected unchanged line */
var splitHunk = function(button)
{
	// Find the selected row (marked with .selected-row class)
	var selectedLine = document.querySelector('.selected-row');
	if (!selectedLine) return false;

	var selectedClass = selectedLine.getAttribute("class") || "";
	if (selectedClass.indexOf("noopline") < 0) return false;

	var selectedIndex = parseInt(selectedLine.getAttribute("index"));
	var hunkHeader = null;
	var hunkHeaderIndex = -1;

	// Find the hunk header by walking siblings
	for (var next = selectedLine.previousSibling; next; next = next.previousSibling) {
		var elem_class = next.getAttribute ? (next.getAttribute("class") || "") : "";
		if (elem_class.indexOf("hunkheader") >= 0) {
			var rawText = next.textContent || next.innerText;
			hunkHeader = extractHunkHeaderLine(rawText);
			hunkHeaderIndex = parseInt(next.getAttribute("index"));
			break;
		}
	}

	if (!hunkHeader) return false;

	// Calculate preselect as the difference in indices (accounts for paired rows)
	var preselect = selectedIndex - hunkHeaderIndex - 1;

	// Parse the original hunk header to get line numbers
	var m;
	if (m = hunkHeader.match(/@@ \-(\d+)(,\d+)? \+(\d+)(,\d+)? @@/)) {
		var start_old = parseInt(m[1]);
		var start_new = parseInt(m[3]);
	} else return false;

	// Get all lines in this hunk
	var subhunkText = getLines(hunkHeader);
	var lines = subhunkText.split('\n');
	lines.shift();  // Remove hunk header
	if (lines[lines.length-1] == "") lines.pop(); // Remove final newline

	// Split the lines at the selected position
	var firstHunkLines = lines.slice(0, preselect);
	var secondHunkLines = lines.slice(preselect + 1); // Skip the splitting line

	// Calculate line counts for each new hunk
	var calculateCounts = function(hunkLines) {
		var oldCount = 0, newCount = 0;
		for (var i = 0; i < hunkLines.length; i++) {
			var firstChar = hunkLines[i].charAt(0);
			if (firstChar == '-') {
				oldCount++;
			} else if (firstChar == '+') {
				newCount++;
			} else {
				oldCount++; 
				newCount++;
			}
		}
		return [oldCount, newCount];
	};

	var firstCounts = calculateCounts(firstHunkLines);
	var secondCounts = calculateCounts(secondHunkLines);

	// Calculate line numbers for second hunk
	var secondStart_old = start_old;
	var secondStart_new = start_new;
	for (var i = 0; i <= preselect; i++) {
		var firstChar = lines[i].charAt(0);
		if (firstChar == '-' || firstChar == ' ') {
			secondStart_old++;
		}
		if (firstChar == '+' || firstChar == ' ') {
			secondStart_new++;
		}
	}

	// Create the two new hunks
	var firstHunk = "";
	if (firstHunkLines.length > 0) {
		firstHunk = diffHeader + '\n' + 
			"@@ -" + start_old + "," + firstCounts[0] + 
			" +" + start_new + "," + firstCounts[1] + " @@\n" +
			firstHunkLines.join('\n') + '\n';
	}

	var secondHunk = "";
	if (secondHunkLines.length > 0) {
		secondHunk = diffHeader + '\n' + 
			"@@ -" + secondStart_old + "," + secondCounts[0] + 
			" +" + secondStart_new + "," + secondCounts[1] + " @@\n" +
			secondHunkLines.join('\n') + '\n';
	}

	// Apply the split by creating a modified diff and refreshing
	var modifiedDiff = originalDiff;
	var originalHunkStart = modifiedDiff.indexOf(hunkHeader);
	var originalHunkEnd = modifiedDiff.indexOf("\n@@", originalHunkStart + 1);
	var originalHunkEnd2 = modifiedDiff.indexOf("\ndiff", originalHunkStart + 1);
	if (originalHunkEnd2 < originalHunkEnd && originalHunkEnd2 > 0)
		originalHunkEnd = originalHunkEnd2;
	if (originalHunkEnd == -1)
		originalHunkEnd = modifiedDiff.length;

	var beforeHunk = modifiedDiff.substring(0, originalHunkStart);
	var afterHunk = modifiedDiff.substring(originalHunkEnd);
	
	var newHunksText = "";
	if (firstHunk) {
		newHunksText += firstHunk.substring(diffHeader.length + 1); // Remove diff header since it's already in modifiedDiff
	}
	if (secondHunk) {
		newHunksText += secondHunk.substring(diffHeader.length + 1); // Remove diff header since it's already in modifiedDiff
	}
	
	modifiedDiff = beforeHunk + newHunksText + afterHunk;
	
	// Refresh the display with the modified diff
	displayDiff(modifiedDiff, originalCached);
}

/* Find all contiguous add/del/change lines. A quick way to select "just this
 * chunk". */
var findsubhunk = function(start) {
	var isChangeRow = function(el) {
		if (!el || !el.getAttribute) return false;
		var cls = el.getAttribute("class") || "";
		return cls.indexOf("delline") >= 0 || cls.indexOf("addline") >= 0 || cls.indexOf("changeline") >= 0;
	};

	var isStopRow = function(el) {
		if (!el || !el.getAttribute) return true;
		var cls = el.getAttribute("class") || "";
		return cls.indexOf("hunkheader") >= 0 || cls.indexOf("noopline") >= 0;
	};

	var findBound = function(direction) {
		var element = start;
		for (var next = element[direction]; next; next = next[direction]) {
			if (isStopRow(next)) break;
			if (isChangeRow(next)) element = next;
		}
		return element;
	};
	return [findBound("previousSibling"), findBound("nextSibling")];
} 

/* Remove existing selection */
var deselect = function() {
	// Remove the selection button first
	var selButton = document.getElementById("selection-button");
	if (selButton) {
		selButton.parentNode.removeChild(selButton);
	}
	// Remove selection class from all rows
	var selectedRows = document.querySelectorAll('.selected-row');
	for (var i = 0; i < selectedRows.length; i++) {
		selectedRows[i].classList.remove('selected-row');
	}
}

/* Stage individual selected lines.  Note that for staging, unselected
 * delete lines are context, and v.v. for unstaging. */
var stageLines = function(reverse) {
	// Find all selected rows (marked with .selected-row class)
	var selectedRows = document.querySelectorAll('.selected-row');
	if (selectedRows.length == 0) return false;
	currentSelection = false;

	// Find the hunk header by walking backwards from first selected row
	var hunkHeader = false;
	var hunkHeaderIndex = -1;

	for (var next = selectedRows[0].previousSibling; next; next = next.previousSibling) {
		var elem_class = next.getAttribute ? (next.getAttribute("class") || "") : "";
		if (elem_class.indexOf("hunkheader") >= 0) {
			var rawText = next.textContent || next.innerText;
			hunkHeader = extractHunkHeaderLine(rawText);
			hunkHeaderIndex = parseInt(next.getAttribute("index"));
			break;
		}
	}

	if (!hunkHeader) return false;

	// Get selected row indices (accounting for paired changelines)
	var selectedIndices = {};
	for (var i = 0; i < selectedRows.length; i++) {
		var child = selectedRows[i];

		var idx = parseInt(child.getAttribute("index"));
		if (!isNaN(idx)) {
			selectedIndices[idx] = true;
			// For paired changelines, also include the add-index
			var addIdx = child.getAttribute("data-add-index");
			if (addIdx) {
				selectedIndices[parseInt(addIdx)] = true;
			}
		}
	}

	var subhunkText = getLines(hunkHeader);
	var lines = subhunkText.split('\n');
	lines.shift();  // Trim old hunk header (we'll compute our own)
	if (lines[lines.length - 1] == "") lines.pop(); // Omit final newline

	var m;
	if (m = hunkHeader.match(/@@ \-(\d+)(,\d+)? \+(\d+)(,\d+)? @@/)) {
		var start_old = parseInt(m[1]);
		var start_new = parseInt(m[3]);
	} else return false;

	// Build patch based on selected indices
	// Each line in the hunk corresponds to hunkHeaderIndex + 1 + lineIndex
	var patch = "", count = [0, 0];
	for (var i = 0; i < lines.length; i++) {
		var l = lines[i];
		var firstChar = l.charAt(0);
		var lineIndex = hunkHeaderIndex + 1 + i;
		var isSelected = selectedIndices[lineIndex];

		if (!isSelected) {    // Not selected
			if (firstChar == (reverse ? '+' : "-"))   // It's context now, make it so!
				l = ' ' + l.substr(1);
			if (firstChar != (reverse ? '-' : "+")) { // Skip unincluded changes
				patch += l + "\n";
				count[0]++; count[1]++;
			}
		} else {                                      // In the selection
			if (firstChar == '-') {
				count[0]++;
			} else if (firstChar == '+') {
				count[1]++;
			} else {
				count[0]++; count[1]++;
			}
			patch += l + "\n";
		}
	}
	patch = diffHeader + '\n' + "@@ -" + start_old.toString() + "," + count[0].toString() +
		" +" + start_new.toString() + "," + count[1].toString() + " @@\n" + patch;

	pendingScrollY = getScrollY();
	addHunkText(patch, reverse);
}

/* Compute the selection before actually making it.  Return as object
 * with 2-element array "bounds", and "good", which indicates if the
 * selection contains add/del lines. */
var computeSelection = function(list, from, to)
{
	var startIndex = parseInt(from.getAttribute("index"));
	var endIndex = parseInt(to.getAttribute("index"));
	if (isNaN(startIndex) || isNaN(endIndex)) {
		return false;
	}

	var up = (startIndex < endIndex);
	var nextelem = up ? "nextSibling" : "previousSibling";

	var isChangeRow = function(el) {
		if (!el || !el.getAttribute) return false;
		var cls = el.getAttribute("class") || "";
		return cls.indexOf("delline") >= 0 || cls.indexOf("addline") >= 0 || cls.indexOf("changeline") >= 0;
	};

	var insel = from.parentNode && from.parentNode.id == "selected";
	var good = false;
	var last = from;

	for (var elem = from; ; elem = elem[nextelem]) {
		if (!insel && elem.id && elem.id == "selected") {
			// Descend into selection div
			elem = up ? elem.childNodes[1] : elem.lastChild;
			insel = true;
		}

		var elem_class = elem.getAttribute ? (elem.getAttribute("class") || "") : "";
		if (elem_class) {
			if (elem_class.indexOf("hunkheader") >= 0) {
				elem = last;
				break; // Stay inside this hunk
			}
			if (!good && isChangeRow(elem)) {
				good = true; // A good selection
			}
		}
		if (elem == to) break;

		if (insel) {
			if (up ?
				elem == elem.parentNode.lastChild :
				elem == elem.parentNode.childNodes[1]) {
				// Come up out of selection div
				last = elem;
				insel = false;
				elem = elem.parentNode;
				continue;
			}
		}
		last = elem;
	}
	to = elem;
	return { bounds: [from, to], good: good };
}


var currentSelection = false;

/* Highlight the selection (if it is new)

   If trust is set, it is assumed that the selection is pre-computed,
   and it is not recomputed.  Trust also assumes deselection has
   already occurred
*/
var showSelection = function(file, from, to, trust)
{
	if (trust)  // No need to compute bounds.
		var sel = { bounds: [from, to], good: true };
	else
		var sel = computeSelection(file, from, to);

	if (!sel) {
		currentSelection = false;
		return;
	}

	if (currentSelection &&
		currentSelection.bounds[0] == sel.bounds[0] &&
		currentSelection.bounds[1] == sel.bounds[1] &&
		currentSelection.good == sel.good) {
		return; // Same selection
	} else {
		currentSelection = sel;
	}

	if (!trust) deselect();

	var beg = parseInt(sel.bounds[0].getAttribute("index"));
	var end = parseInt(sel.bounds[1].getAttribute("index"));

	if (beg > end) {
		var tmp = beg;
		beg = end;
		end = tmp;
	}

	// Collect elements by walking siblings (handles side-by-side structure)
	var elementList = [];
	var linesContainer = from.parentNode;
	if (linesContainer.classList && linesContainer.classList.contains('selected-row')) {
		linesContainer = linesContainer.parentNode;
	}

	// Find elements by index
	var children = linesContainer.children;
	for (var i = 0; i < children.length; i++) {
		var child = children[i];
		var idx = parseInt(child.getAttribute("index"));
		if (!isNaN(idx) && idx >= beg && idx <= end) {
			elementList.push(child);
		}
	}

	if (elementList.length == 0) return;

	// Mark selected rows with a class (don't wrap them)
	for (var i = 0; i < elementList.length; i++) {
		elementList[i].classList.add('selected-row');
	}

	// Check if this is a single unchanged line selection for split hunk functionality
	var firstClass = elementList[0].getAttribute("class") || "";
	var isSingleUnchangedLine = (elementList.length == 1 && firstClass.indexOf("noopline") >= 0);

	// Create button - position it absolutely within the first selected row
	var link = document.createElement('a');
	link.setAttribute("href", "#");
	link.setAttribute("id", "selection-button");

	if (isSingleUnchangedLine) {
		link.appendChild(document.createTextNode("Split hunk"));
		link.setAttribute("class", "hunkbutton selection-action");
		link.setAttribute('onclick', 'splitHunk(this); return false;');
	} else {
		link.appendChild(document.createTextNode(
			(originalCached ? "Uns" : "S") + "tage line" +
			(elementList.length > 1 ? "s" : "")));
		link.setAttribute("class", "hunkbutton selection-action");

		if (sel.good) {
			link.setAttribute('onclick', 'stageLines(' +
				(originalCached ? 'true' : 'false') +
				'); return false;');
		} else {
			link.setAttribute("class", "hunkbutton selection-action disabled");
		}
	}

	// Insert button into the first selected row
	elementList[0].insertBefore(link, elementList[0].firstChild);
}


var handleCommitNativeMessage = function (message) {
  if (!message || typeof message.type !== "string") return;
  switch (message.type) {
    case "commitState":
      if (typeof setState === "function") {
        var stateText = typeof message.state === "undefined" ? "" : String(message.state);
        setState(stateText);
      }
      break;
    case "commitHunkApplied":
      // Hunk was successfully staged/unstaged/discarded
      // Request fresh diff - pendingScrollY will be restored in displayDiff
      requestCommitDiff();
      break;
    case "commitSelectionChanged":
      handleCommitSelectionChanged(message);
      break;
    case "commitDiff":
      if (!currentCommitSelection || !currentCommitSelection.file) {
        return;
      }
      var responsePath = "";
      if (typeof message.path !== "undefined" && message.path !== null)
        responsePath = message.path.toString();
      if (
        currentCommitSelection.path &&
        responsePath &&
        responsePath !== currentCommitSelection.path
      ) {
        return;
      }
      showFileChanges(
        currentCommitSelection.file,
        !!currentCommitSelection.cached,
        message
      );
      break;
    case "commitMultipleSelection":
      currentCommitSelection = null;
      if (typeof showMultipleFilesSelection === "function") {
        try {
          var files = [];
          if (
            message &&
            message.files &&
            Object.prototype.toString.call(message.files) === "[object Array]"
          ) {
            files = message.files;
          }
          showMultipleFilesSelection(files);
        } catch (error) {
          if (window.console && console.error) {
            console.error("commitMultipleSelection handler failed", error);
          }
        }
      }
      break;
  }
};

gitxBridge.subscribe(handleCommitNativeMessage);
