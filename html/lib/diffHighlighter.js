var gitxDiffLog = function() {
	if (window.console && console.log)
		console.log.apply(console, arguments);
};

var toggleDiff = function(id)
{
  var content = document.getElementById('content_' + id);
  if (content) {
    var collapsed = (content.style.display == 'none');
    if (collapsed) {
      content.style.display = 'block';
    } else {
      content.style.display = 'none';
    }
	
    var title = document.getElementById('title_' + id);
    if (title) {
      if (collapsed) {
        title.classList.remove('collapsed');
        title.classList.add('expanded');
      }
      else {
        title.classList.add('collapsed');
        title.classList.remove('expanded');
      }
    }
  }
}

var highlightDiff = function(diff, element, callbacks) {
	if (!diff || diff == "")
		return;

	if (!callbacks)
		callbacks = {};
	var start = new Date().getTime();
	element.className = "diff"
	var content = diff;  // Don't escape here - escape when building HTML

	var file_index = 0;

	var startname = "";
	var endname = "";
	var diffLines = [];  // Array of line objects for side-by-side processing
	var finalContent = "";
	var lines = content.split('\n');
	var binary = false;
	var mode_change = false;
	var old_mode = "";
	var new_mode = "";
	var linkToTop = "<div class=\"top-link\"><a href=\"#\">Top</a></div>";

	var hunk_start_line_1 = -1;
	var hunk_start_line_2 = -1;

	var header = false;

	var finishContent = function()
	{
		if (!file_index)
		{
			file_index++;
			return;
		}

		if (callbacks["newfile"])
			callbacks["newfile"](startname, endname, "file_index_" + (file_index - 1), mode_change, old_mode, new_mode);

		var title = startname;
		var binaryname = endname;
		if (endname == "/dev/null") {
			binaryname = startname;
			title = startname;
		}
		else if (startname == "/dev/null")
			title = endname;
		else if (startname != endname)
			title = startname + " renamed to " + endname;

		if (binary && endname == "/dev/null") {
			diffLines = [];
			file_index++;
			startname = "";
			endname = "";
			return;
		}

		if (diffLines.length > 0 || binary) {
			var escapedTitle = title.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, "\\'");
			finalContent += '<div class="file" id="file_index_' + (file_index - 1) + '">' +
				'<div id="title_' + escapedTitle + '" class="expanded fileHeader"><a href="javascript:toggleDiff(\'' + escapedTitle + '\');">' + escapedTitle + '</a></div>';
		}

		if (!binary && diffLines.length > 0)  {
			finalContent += '<div id="content_' + escapedTitle + '" class="diffContent">' +
				'<div class="lines">' + buildSideBySideHtml(diffLines).replace(/\t/g, "    ") + "</div>" +
				'</div>';
		}
		else {
			if (binary) {
				if (callbacks["binaryFile"])
					finalContent += callbacks["binaryFile"](binaryname);
				else
					finalContent += '<div id="content_' + escapedTitle + '">Binary file differs</div>';
			}
		}

		if (diffLines.length > 0 || binary)
			finalContent += '</div>' + linkToTop;

		diffLines = [];
		file_index++;
		startname = "";
		endname = "";
	}

	for (var lineno = 0, lindex = 0; lineno < lines.length; lineno++) {
		var l = lines[lineno];

		var firstChar = l.charAt(0);

		if (firstChar == "d" && l.charAt(1) == "i") {
			header = true;
			finishContent();
			binary = false;
			mode_change = false;

			if(match = l.match(/^diff --git (a\/)+(.*) (b\/)+(.*)$/)) {
				startname = match[2];
				endname = match[4];
			}
			continue;
		}

		if (header) {
			if (firstChar == "n") {
				if (l.match(/^new file mode .*$/))
					startname = "/dev/null";
				if (match = l.match(/^new mode (.*)$/)) {
					mode_change = true;
					new_mode = match[1];
				}
				continue;
			}
			if (firstChar == "o") {
				if (match = l.match(/^old mode (.*)$/)) {
					mode_change = true;
					old_mode = match[1];
				}
				continue;
			}
			if (firstChar == "d") {
				if (l.match(/^deleted file mode .*$/))
					endname = "/dev/null";
				continue;
			}
			if (firstChar == "-") {
				if (match = l.match(/^--- (a\/)?(.*)$/))
					startname = match[2];
				continue;
			}
			if (firstChar == "+") {
				if (match = l.match(/^\+\+\+ (b\/)?(.*)$/))
					endname = match[2];
				continue;
			}
			if (firstChar == 'r') {
				if (match = l.match(/^rename (from|to) (.*)$/)) {
					if (match[1] == "from")
						startname = match[2];
					else
						endname = match[2];
				}
				continue;
			}
			if (firstChar == "B") {
				binary = true;
				if (match = l.match(/^Binary files (a\/)?(.*) and (b\/)?(.*) differ$/)) {
					startname = match[2];
					endname = match[4];
				}
			}
			if (firstChar == "@")
				header = false;
			else
				continue;
		}

		// Collect line data for side-by-side processing
		if (firstChar == "+") {
			diffLines.push({
				type: 'add',
				index: lindex,
				content: l,
				lineNum: ++hunk_start_line_2
			});
		} else if (firstChar == "-") {
			diffLines.push({
				type: 'del',
				index: lindex,
				content: l,
				lineNum: ++hunk_start_line_1
			});
		} else if (firstChar == "@") {
			if (header) {
				header = false;
			}
			if (m = l.match(/@@ \-([0-9]+),?\d* \+(\d+),?\d* @@/)) {
				hunk_start_line_1 = parseInt(m[1]) - 1;
				hunk_start_line_2 = parseInt(m[2]) - 1;
			}
			diffLines.push({
				type: 'hunk',
				index: lindex,
				content: l
			});
		} else if (firstChar == " ") {
			diffLines.push({
				type: 'context',
				index: lindex,
				content: l,
				oldLineNum: ++hunk_start_line_1,
				newLineNum: ++hunk_start_line_2
			});
		}
		lindex++;
	}

	finishContent();

	element.innerHTML = finalContent;

	if (false)
		gitxDiffLog("Total time:" + (new Date().getTime() - start));
}

// Build side-by-side HTML from collected diff lines
var buildSideBySideHtml = function(diffLines) {
	var html = '';
	var i = 0;

	// Helper to escape content for HTML display
	var escapeContent = function(text) {
		if (!text) return '';
		return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
	};

	while (i < diffLines.length) {
		var line = diffLines[i];

		if (line.type === 'hunk') {
			// Hunk header spans both sides
			html += '<div index="' + line.index + '" class="hunkheader">' + escapeContent(line.content) + '</div>';
			i++;
		} else if (line.type === 'context') {
			// Context lines appear on both sides - escape content, strip leading space
			var escapedContent = escapeContent(line.content.substring(1));
			html += buildRow(line.index, 'noopline', line.oldLineNum, escapedContent, line.newLineNum, escapedContent);
			i++;
		} else if (line.type === 'del' || line.type === 'add') {
			// Collect consecutive del/add blocks for pairing
			var delLines = [];
			var addLines = [];

			// First collect all deletions
			while (i < diffLines.length && diffLines[i].type === 'del') {
				delLines.push(diffLines[i]);
				i++;
			}
			// Then collect all additions
			while (i < diffLines.length && diffLines[i].type === 'add') {
				addLines.push(diffLines[i]);
				i++;
			}

			// Apply inline diff highlighting if we have both deletions and additions
			if (delLines.length > 0 && addLines.length > 0) {
				var highlighted = highlightChangePair(delLines, addLines);
				delLines = highlighted.del;
				addLines = highlighted.add;
			} else if (delLines.length > 0) {
				// Only deletions - apply simple highlighting (strip leading -)
				for (var d = 0; d < delLines.length; d++) {
					var text = delLines[d].content.substring(1);
					delLines[d].highlighted = '<del>' + inlinediff.escape(text) + '</del>';
				}
			} else if (addLines.length > 0) {
				// Only additions - apply simple highlighting (strip leading +)
				for (var a = 0; a < addLines.length; a++) {
					var text = addLines[a].content.substring(1);
					addLines[a].highlighted = '<ins>' + highlightTrailingWhitespace(inlinediff.escape(text)) + '</ins>';
				}
			}

			// Helper to get display content - use highlighted if set (even if empty), else strip prefix from content
			var getDisplayContent = function(line) {
				if (line.highlighted !== undefined) return line.highlighted;
				return escapeContent(line.content.substring(1));
			};

			// Build paired rows
			var maxRows = Math.max(delLines.length, addLines.length);
			for (var r = 0; r < maxRows; r++) {
				var delLine = delLines[r];
				var addLine = addLines[r];

				// Determine the index - use the line that exists, prefer del
				var rowIndex = delLine ? delLine.index : addLine.index;

				if (delLine && addLine) {
					// Both sides have content - include add index for staging
					html += buildRow(rowIndex, 'changeline',
						delLine.lineNum, getDisplayContent(delLine),
						addLine.lineNum, getDisplayContent(addLine),
						'delline', 'addline', addLine.index);
				} else if (delLine) {
					// Only deletion
					html += buildRow(delLine.index, 'delline',
						delLine.lineNum, getDisplayContent(delLine),
						'', '',
						'delline', 'empty');
				} else if (addLine) {
					// Only addition
					html += buildRow(addLine.index, 'addline',
						'', '',
						addLine.lineNum, getDisplayContent(addLine),
						'empty', 'addline');
				}
			}
		} else {
			i++;
		}
	}

	return html;
};

// Apply inline diff highlighting to paired del/add blocks
var highlightChangePair = function(delLines, addLines) {
	var oldText = delLines.map(function(l) { return l.content.substring(1); }).join("\n");
	var newText = addLines.map(function(l) { return l.content.substring(1); }).join("\n");

	var diffResult = inlinediff.diffString3(oldText, newText);
	var oldHighlighted = diffResult[1].split(/\n/);
	var newHighlighted = diffResult[2].split(/\n/);

	// Strip leading +/- since colors indicate add/del
	for (var d = 0; d < delLines.length; d++) {
		delLines[d].highlighted = mergeInsDel(oldHighlighted[d] || '');
	}
	for (var a = 0; a < addLines.length; a++) {
		addLines[a].highlighted = mergeInsDel(highlightTrailingWhitespace(newHighlighted[a] || ''));
	}

	return { del: delLines, add: addLines };
};

// Build a single row of the side-by-side diff
var buildRow = function(index, rowClass, oldLineNum, oldContent, newLineNum, newContent, oldClass, newClass, addIndex) {
	oldClass = oldClass || rowClass;
	newClass = newClass || rowClass;

	var oldLineNumStr = (oldLineNum === '' || oldLineNum === undefined) ? '' : oldLineNum;
	var newLineNumStr = (newLineNum === '' || newLineNum === undefined) ? '' : newLineNum;
	var oldContentStr = oldContent || '';
	var newContentStr = newContent || '';

	var addIndexAttr = (addIndex !== undefined) ? ' data-add-index="' + addIndex + '"' : '';

	return '<div index="' + index + '"' + addIndexAttr + ' class="diff-row ' + rowClass + '">' +
		'<div class="lineno old-lineno">' + oldLineNumStr + '</div>' +
		'<div class="line-content old-content ' + oldClass + '">' + oldContentStr + '</div>' +
		'<div class="lineno new-lineno">' + newLineNumStr + '</div>' +
		'<div class="line-content new-content ' + newClass + '">' + newContentStr + '</div>' +
		'</div>';
}

var highlightTrailingWhitespace = function (l) {
	// Highlight trailing whitespace
	l = l.replace(/(\s+)(<\/ins>)?$/, '<span class="whitespace">$1</span>$2');
	return l;
}

var mergeInsDel = function (html) {
	return html
		.replace(/^<\/(ins|del)>|<(ins|del)>$/g,'')
		.replace(/<\/(ins|del)><\1>/g,'');
}

var postProcessDiffContents = function(diffContent) {
	// Parse HTML string to DOM elements
	var tempDiv = document.createElement('div');
	tempDiv.innerHTML = diffContent;
	var diffElements = tempDiv.children;
	
	var newContent = "";
	var oldEls = [];
	var newEls = [];
	
	// Helper to get text content of an element
	var getElementText = function(el) {
		return el.textContent || el.innerText || '';
	};
	
	// Helper to set HTML content of an element
	var setElementHTML = function(el, html) {
		el.innerHTML = html;
	};
	
	// Helper to get outer HTML of an element
	var getOuterHTML = function(el) {
		return el.outerHTML;
	};
	
	var flushBuffer = function () {
		if (oldEls.length || newEls.length) {
			var buffer = "";
			if (!oldEls.length || !newEls.length) {
				// hunk only contains additions OR deletions, so there is no need
				// to do any inline-diff. just keep the elements as they are
				var elements = oldEls.length ? oldEls : newEls;
				buffer = elements.map(function(e) {
					var text = getElementText(e);
					var prefix = text.substring(0,1);
					var content = inlinediff.escape(text.substring(1));
					var tag = prefix=='+' ? 'ins' : 'del';
					var html = prefix+'<'+tag+'>'+(prefix == "+" ? highlightTrailingWhitespace(content) : content)+'</'+tag+'>';
					setElementHTML(e, html);
					return getOuterHTML(e);
				}).join("");
			}
			else {
				// hunk contains additions AND deletions. so we create an inline diff
				// of all the old and new lines together and merge the result back to buffer
				var mapFn = function (e) { 
					var text = getElementText(e);
					return text.substring(1).replace(/\r?\n|\r/g,''); 
				};
				var oldText = oldEls.map(mapFn).join("\n");
				var newText = newEls.map(mapFn).join("\n");
				var diffResult = inlinediff.diffString3(oldText,newText);
				var diffLines = (diffResult[1] + "\n" + diffResult[2]).split(/\n/g);
				
				buffer = oldEls.map(function(e, i) {
					var di = i;
					setElementHTML(e, "-"+mergeInsDel(diffLines[di]));
					return getOuterHTML(e);
				}).join("") + newEls.map(function(e, i) {
					var di = i + oldEls.length;
					var line = mergeInsDel(highlightTrailingWhitespace(diffLines[di]));
					setElementHTML(e, "+"+line);
					return getOuterHTML(e);
				}).join("");
			}
			newContent+= buffer;
			oldEls = [];
			newEls = [];
		}
	};
	
	// Process each element
	for (var i = 0; i < diffElements.length; i++) {
		var e = diffElements[i];
		var isAdd = e.classList.contains("addline");
		var isDel = e.classList.contains("delline");
		var html = getOuterHTML(e);
		
		if (isAdd) {
			newEls.push(e);
		}
		else if (isDel) {
			oldEls.push(e);
		}
		else {
			flushBuffer();
			newContent+= html;
		}
	}
	flushBuffer();
	return newContent; 
}


/*
 * Javascript Diff Algorithm
 *  By John Resig (http://ejohn.org/)
 *  Modified by Chu Alan "sprite"
 *  Adapted for GitX by Mathias Leppich http://github.com/muhqu
 *
 * Released under the MIT license.
 *
 * More Info:
 *  http://ejohn.org/projects/javascript-diff-algorithm/
 */

var inlinediff = (function () {
  return {
    diffString: diffString,
    diffString3: diffString3,
    escape: escape
  };

  function escape(s) {
      var n = s;
      n = n.replace(/&/g, "&amp;");
      n = n.replace(/</g, "&lt;");
      n = n.replace(/>/g, "&gt;");
      n = n.replace(/"/g, "&quot;");
      return n;
  }

  function diffString( o, n ) {
    o = o.replace(/\s+$/, '');
    n = n.replace(/\s+$/, '');

    var out = diff(o == "" ? [] : o.split(/\s+/), n == "" ? [] : n.split(/\s+/) );
    var str = "";

    var oSpace = o.match(/\s+/g);
    if (oSpace == null) {
      oSpace = ["\n"];
    } else {
      oSpace.push("\n");
    }
    var nSpace = n.match(/\s+/g);
    if (nSpace == null) {
      nSpace = ["\n"];
    } else {
      nSpace.push("\n");
    }

    if (out.n.length == 0) {
        for (var i = 0; i < out.o.length; i++) {
          str += '<del>' + escape(out.o[i]) + oSpace[i] + "</del>";
        }
    } else {
      if (out.n[0].text == null) {
        for (n = 0; n < out.o.length && out.o[n].text == null; n++) {
          str += '<del>' + escape(out.o[n]) + oSpace[n] + "</del>";
        }
      }

      for ( var i = 0; i < out.n.length; i++ ) {
        if (out.n[i].text == null) {
          str += '<ins>' + escape(out.n[i]) + nSpace[i] + "</ins>";
        } else {
          var pre = "";

          for (n = out.n[i].row + 1; n < out.o.length && out.o[n].text == null; n++ ) {
            pre += '<del>' + escape(out.o[n]) + oSpace[n] + "</del>";
          }
          str += escape(out.n[i].text) + nSpace[i] + pre;
        }
      }
    }
    
    return str;
  }

  function whitespaceAwareTokenize(n) {
    return n !== "" && n.match(/\n| *[\-><!=]+ *|[ \t]+|[<$&#§%]\w+|\w+|\W/g) || [];
  }

  function tag(t,c) {
    if (t === "") return escape(c);
    return c==="" ? '' : '<'+t+'>'+escape(c)+'</'+t+'>';
  }
  
  function diffString3( o, n ) {
    var out = diff(whitespaceAwareTokenize(o), whitespaceAwareTokenize(n));
    var ac = [], ao = [], an = [];
    if (out.n.length == 0) {
        for (var i = 0; i < out.o.length; i++) {
          ac.push(tag('del',out.o[i]));
          ao.push(tag('del',out.o[i]));
        }
    } else {
      if (out.n[0].text == null) {
        for (n = 0; n < out.o.length && out.o[n].text == null; n++) {
          ac.push(tag('del',out.o[n]));
        }
      }

      var added = 0;
      for ( var i = 0; i < out.o.length; i++ ) {
        if (out.o[i].text == null) {
          ao.push(tag('del',out.o[i])); added++;
        } else {
          var moved = (i - out.o[i].row - added);
          ao.push(tag((moved>0) ? 'del' : '',out.o[i].text));
        }
      }

      var removed = 0;
      for ( var i = 0; i < out.n.length; i++ ) {
        if (out.n[i].text == null) {
          ac.push(tag('ins',out.n[i]));
          an.push(tag('ins',out.n[i]));
        } else {
          var moved = (i - out.n[i].row + removed);
          an.push(tag((moved<0)?'ins':'', out.n[i].text));
          ac.push(escape(out.n[i].text));
          for (n = out.n[i].row + 1; n < out.o.length && out.o[n].text == null; n++ ) {
            ac.push(tag('del',out.o[n])); removed++;
          }
        }
      }
    }
    return [
      ac.join(""), // anotated combined additions and deletions
      ao.join(""), // old with highlighted deletions
      an.join("")  // new with highlighted additions
    ];
  }

  function diff( o, n ) {
    var ns = {}, os = {}, k = null, i = 0;
    
    for ( var i = 0; i < n.length; i++ ) {
      k = '"' + n[i]; // prefix keys with a quote to not collide with Object's internal keys, e.g. '__proto__' or 'constructor'
      if ( ns[k] === undefined )
        ns[k] = { rows: [], o: null };
      ns[k].rows.push( i );
    }
    
    for ( var i = 0; i < o.length; i++ ) {
      k = '"' + o[i]
      if ( os[k] === undefined )
        os[k] = { rows: [], n: null };
      os[k].rows.push( i );
    }
    
    for ( var k in ns ) {
      if ( ns[k].rows.length == 1 && os[k] !== undefined && os[k].rows.length == 1 ) {
        n[ ns[k].rows[0] ] = { text: n[ ns[k].rows[0] ], row: os[k].rows[0] };
        o[ os[k].rows[0] ] = { text: o[ os[k].rows[0] ], row: ns[k].rows[0] };
      }
    }
    
    for ( var i = 0; i < n.length - 1; i++ ) {
      if ( n[i].text != null && n[i+1].text == null && n[i].row + 1 < o.length && o[ n[i].row + 1 ].text == null && 
           n[i+1] == o[ n[i].row + 1 ] ) {
        n[i+1] = { text: n[i+1], row: n[i].row + 1 };
        o[n[i].row+1] = { text: o[n[i].row+1], row: i + 1 };
      }
    }
    
    for ( var i = n.length - 1; i > 0; i-- ) {
      if ( n[i].text != null && n[i-1].text == null && n[i].row > 0 && o[ n[i].row - 1 ].text == null && 
           n[i-1] == o[ n[i].row - 1 ] ) {
        n[i-1] = { text: n[i-1], row: n[i].row - 1 };
        o[n[i].row-1] = { text: o[n[i].row-1], row: i - 1 };
      }
    }
    
    return { o: o, n: n };
  }
})();
