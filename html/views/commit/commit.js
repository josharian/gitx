/* Commit: Interface for selecting, staging, discarding, and unstaging
   hunks, individual lines, or ranges of lines.  */

var contextLines = 0;

var showNewFile = function(file)
{
	setTitle("New file: " + file.path.escapeHTML());

	var contents = Index.diffForFile_staged_contextLines_(file, false, contextLines);
	if (!contents) {
		notify("Can not display changes (Binary file?)", -1);
		diff.innerHTML = "";
		return;
	}

	diff.innerHTML = "<pre>" + contents.escapeHTML() + "</pre>";
	diff.style.display = '';
}

var hideState = function() {
	$("state").style.display = "none";
}

var setState = function(state) {
	setTitle(state);
	hideNotification();
	$("state").style.display = "";
	$("diff").style.display = "none";
	$("state").innerHTML = state.escapeHTML();
}

var setTitle = function(status) {
	$("status").innerHTML = status;
	$("contextSize").style.display = "none";
	$("contextTitle").style.display = "none";
}

var displayContext = function() {
	$("contextSize").style.display = "";
	$("contextTitle").style.display = "";
	contextLines = $("contextSize").value;
}

var showFileChanges = function(file, cached) {
	if (!file) {
		setState("No file selected");
		return;
	}

	hideNotification();
	hideState();

	$("contextSize").oninput = function(element) {
		contextLines = $("contextSize").value;
		Controller.refresh();
	}

	if (file.status == 0) // New file?
		return showNewFile(file);

	setTitle((cached ? "Staged": "Unstaged") + " changes for " + file.path.escapeHTML());
	displayContext();
	var changes = Index.diffForFile_staged_contextLines_(file, cached, contextLines);
	

	if (changes == "") {
		notify("This file has no more changes", 1);
		return;
	}

	displayDiff(changes, cached);
}

var findParentElementByTag = function (el, tagName)
{
	tagName = tagName.toUpperCase();
	while (el && el.tagName != tagName && el.parentNode) {
		el = el.parentNode;
	}
	return el;
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
			var target = findParentElementByTag(event.target, "div");
			var file = target.parentNode;
			if (file.id = "selected")
				file = file.parentNode;
			var start = target;
			var elem_class = start.getAttribute("class");
			if(!elem_class || !(elem_class == "addline" | elem_class == "delline")) 
				return false;
			deselect();
			var bounds = findsubhunk(start);
			showSelection(file,bounds[0],bounds[1],true);
			return false;
		};

		file.onmousedown = function(event) {
			if (event.which != 1) 
				return false;
			var elem_class = event.target.getAttribute("class")
			event.stopPropagation();
			if (elem_class == "hunkheader" || elem_class == "hunkbutton")
				return false;

			var target = findParentElementByTag(event.target, "div");
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

			var srcElement = findParentElementByTag(event.srcElement, "div");
			file.onmouseover = function(event2) {
				var target2 = findParentElementByTag(event2.target, "div");
				showSelection(file, srcElement, target2);
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

var displayDiff = function(diff, cached)
{
	diffHeader = diff.split("\n").slice(0,4).join("\n");
	originalDiff = diff;
	originalCached = cached;

	$("diff").style.display = "";
	highlightDiff(diff, $("diff"));
	hunkHeaders = $("diff").getElementsByClassName("hunkheader");

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
	//window.console.log((reverse?"Removing":"Adding")+" hunk: \n\t"+hunkText);
	if (Controller.stageHunk_reverse_)
		Controller.stageHunk_reverse_(hunkText, reverse);
	else
		alert(hunkText);
}

/* Add the hunk located below the current element */
var addHunk = function(hunk, reverse)
{
	addHunkText(getFullHunk(hunk),reverse);
}

var discardHunk = function(hunk, event)
{
	var hunkText = getFullHunk(hunk);

	if (Controller.discardHunk_altKey_) {
		Controller.discardHunk_altKey_(hunkText, event.altKey == true);
	} else {
		alert(hunkText);
	}
}

/* Split a hunk at the selected unchanged line */
var splitHunk = function(button)
{
	var selection = document.getElementById("selected");
	if (!selection) return false;
	
	var selectedLine = selection.childNodes[1]; // First child is the button, second is the line
	if (!selectedLine || selectedLine.getAttribute("class") != "noopline") return false;
	
	var selectedIndex = parseInt(selectedLine.getAttribute("index"));
	var hunkHeader = null;
	var preselect = 0;

	// Find the hunk header
	for(var next = selection.previousSibling; next; next = next.previousSibling) {
		var elem_class = next.getAttribute("class");
		if(elem_class == "hunkheader") {
			hunkHeader = next.lastChild.data;
			break;
		}
		preselect++;
	}

	if (!hunkHeader) return false;

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

/* Find all contiguous add/del lines. A quick way to select "just this
 * chunk". */
var findsubhunk = function(start) { 
        var findBound = function(direction) { 
		var element=start;
                for (var next = element[direction]; next; next = next[direction]) { 
                        var elem_class = next.getAttribute("class"); 
                        if (elem_class == "hunkheader" || elem_class == "noopline") 
                                break; 
			element=next;
		}
		return element; 
        }
        return [findBound("previousSibling"), findBound("nextSibling")]; 
} 

/* Remove existing selection */
var deselect = function() {
	var selection = document.getElementById("selected");
	if (selection) {
		while (selection.childNodes[1])
			selection.parentNode.insertBefore(selection.childNodes[1], selection);
		selection.parentNode.removeChild(selection);
	}
}

/* Stage individual selected lines.  Note that for staging, unselected
 * delete lines are context, and v.v. for unstaging. */
var stageLines = function(reverse) {
	var selection = document.getElementById("selected");
	if(!selection) return false;
	currentSelection = false;
	var hunkHeader = false;
	var preselect = 0,elem_class;

	for(var next = selection.previousSibling; next; next = next.previousSibling) {
		elem_class = next.getAttribute("class");
		if(elem_class == "hunkheader") {
			hunkHeader = next.lastChild.data;
			break;
		}
		preselect++;
	}

	if (!hunkHeader) return false;

	var sel_len = selection.children.length-1;
	var subhunkText = getLines(hunkHeader);
	var lines = subhunkText.split('\n');
	lines.shift();  // Trim old hunk header (we'll compute our own)
	if (lines[lines.length-1] == "") lines.pop(); // Omit final newline

	var m;
	if (m = hunkHeader.match(/@@ \-(\d+)(,\d+)? \+(\d+)(,\d+)? @@/)) {
		var start_old = parseInt(m[1]);
		var start_new = parseInt(m[3]);
	} else return false;

	var patch = "", count = [0,0];
	for (var i = 0; i < lines.length; i++) {
		var l = lines[i];
		var firstChar = l.charAt(0);
		if (i < preselect || i >= preselect+sel_len) {    // Before/after select
			if(firstChar == (reverse?'+':"-"))   // It's context now, make it so!
				l = ' '+l.substr(1);
			if(firstChar != (reverse?'-':"+")) { // Skip unincluded changes
				patch += l+"\n";
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
			patch += l+"\n";
		}
	}
	patch = diffHeader + '\n' + "@@ -" + start_old.toString() + "," + count[0].toString() +
		" +" + start_new.toString() + "," + count[1].toString() + " @@\n"+patch;

	addHunkText(patch,reverse);
}

/* Compute the selection before actually making it.  Return as object
 * with 2-element array "bounds", and "good", which indicates if the
 * selection contains add/del lines. */
var computeSelection = function(list, from,to)
{
	var startIndex = parseInt(from.getAttribute("index"));
	var endIndex = parseInt(to.getAttribute("index"));
	if (startIndex == -1 || endIndex == -1) {
		return false;
	}

	var up = (startIndex < endIndex);
	var nextelem = up?"nextSibling":"previousSibling";

	var insel = from.parentNode && from.parentNode.id == "selected";
	var good = false;
	for(var elem = last = from;;elem = elem[nextelem]) {
		if(!insel && elem.id && elem.id == "selected") {
			// Descend into selection div
			elem = up?elem.childNodes[1]:elem.lastChild;
			insel = true;
		}

		var elem_class = elem.getAttribute("class");
		if(elem_class) {
			if(elem_class == "hunkheader") {
				elem = last;
				break; // Stay inside this hunk
			}
			if(!good && (elem_class == "addline" || elem_class == "delline"))
				good = true; // A good selection
		}
		if (elem == to) break;

		if (insel) {
			if (up?
			    elem == elem.parentNode.lastChild:
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
	return {bounds:[from,to],good:good};
}


var currentSelection = false;

/* Highlight the selection (if it is new) 

   If trust is set, it is assumed that the selection is pre-computed,
   and it is not recomputed.  Trust also assumes deselection has
   already occurred
*/
var showSelection = function(file, from, to, trust)
{
	if(trust)  // No need to compute bounds.
		var sel = {bounds:[from,to],good:true};
	else 
		var sel = computeSelection(file,from,to);
        
	if (!sel) {
		currentSelection = false;
		return;
	}

	if(currentSelection &&
	   currentSelection.bounds[0] == sel.bounds[0] &&
	   currentSelection.bounds[1] == sel.bounds[1] &&
	   currentSelection.good == sel.good) {
		return; // Same selection
	} else {
		currentSelection = sel;
	}

	if(!trust) deselect();

	var beg = parseInt(sel.bounds[0].getAttribute("index"));
	var end = parseInt(sel.bounds[1].getAttribute("index"));

	if (beg > end) { 
		var tmp = beg; 
		beg = end; 
		end = tmp; 
	} 

	var elementList = [];
	for (var i = beg; i <= end; ++i) 
		elementList.push(from.parentNode.childNodes[i]); 
	
	var selection = document.createElement("div");
	selection.setAttribute("id", "selected");

	// Check if this is a single unchanged line selection for split hunk functionality
	var isSingleUnchangedLine = (elementList.length == 1 && 
								elementList[0].getAttribute("class") == "noopline");

	var button = document.createElement('a');
	button.setAttribute("href","#");
	
	if (isSingleUnchangedLine) {
		button.appendChild(document.createTextNode("Split hunk"));
		button.setAttribute("class","hunkbutton");
		button.setAttribute("id","splithunk");
		button.setAttribute('onclick','splitHunk(this); return false;');
	} else {
		button.appendChild(document.createTextNode(
					   (originalCached?"Uns":"S")+"tage line"+
					   (elementList.length > 1?"s":"")));
		button.setAttribute("class","hunkbutton");
		button.setAttribute("id","stagelines");

		if (sel.good) {
			button.setAttribute('onclick','stageLines('+
					    (originalCached?'true':'false')+
					    '); return false;');
		} else {
			button.setAttribute("class","disabled");
		}
	}
	selection.appendChild(button);

	file.insertBefore(selection, from);
	for (i = 0; i < elementList.length; i++)
		selection.appendChild(elementList[i]);
}


