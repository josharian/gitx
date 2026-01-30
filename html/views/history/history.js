var commit;

var isArray = function (value) {
  return Object.prototype.toString.call(value) === "[object Array]";
};

// Create a new Commit object
// data: plain object provided by the native bridge
var Commit = function (data) {
  data = data || {};
  this.refs = isArray(data.refs) ? data.refs : [];
  this.author_name = data.authorName || data.author || "";
  this.committer_name = data.committerName || data.committer || "";
  this.sha = data.sha || data.realSha || "";
  this.shortSha = data.shortSha || "";
  this.gitHubUrl = data.gitHubUrl || "";
  this.parents = isArray(data.parents) ? data.parents : [];
  this.subject = data.subject || "";
  this.currentRef = typeof data.currentRef !== "undefined" ? data.currentRef : null;
  this.notificationID = null;
  this.fullyLoaded = !!data.fullyLoaded;

  // This can be called later with the output of
  // 'git show' to fill in missing commit details (such as a diff)
  this.parseDetails = function (details) {
    this.raw = details;

    var diffStart = this.raw.indexOf("\ndiff ");
    var messageStart = this.raw.indexOf("\n\n") + 2;

    if (diffStart > 0) {
      this.message = this.raw
        .substring(messageStart, diffStart)
        .replace(/^    /gm, "")
        .escapeHTML();
      this.diff = this.raw.substring(diffStart);
    } else {
      this.message = this.raw
        .substring(messageStart)
        .replace(/^    /gm, "")
        .escapeHTML();
      this.diff = "";
    }
    this.header = this.raw.substring(0, messageStart);

    if (typeof this.header !== "undefined") {
      var match = this.header.match(/\nauthor (.*) <(.*@.*|.*)> ([0-9].*)/);
      if (typeof match !== "undefined" && typeof match[2] !== "undefined") {
        if (
          !match[2].match(
            /@[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/
          )
        )
          this.author_email = match[2];

        if (typeof match[3] !== "undefined")
          this.author_date = new Date(parseInt(match[3], 10) * 1000);

        match = this.header.match(/\ncommitter (.*) <(.*@.*|.*)> ([0-9].*)/);
        if (typeof match[2] !== "undefined") this.committer_email = match[2];
        if (typeof match[3] !== "undefined")
          this.committer_date = new Date(parseInt(match[3], 10) * 1000);
      }
    }
  };

  this.updateFromData = function (update) {
    if (!update) return;
    if (isArray(update.refs)) {
      this.refs = update.refs;
    }
    if (typeof update.currentRef !== "undefined") {
      this.currentRef = update.currentRef;
    }
  };
};

var setGravatar = function (email, image) {
  if (!email) {
    image.src = "http://www.gravatar.com/avatar/?d=wavatar&s=128";
    return;
  }

  image.src =
    "http://www.gravatar.com/avatar/" +
    hex_md5(email.toLowerCase().replace(/ /g, "")) +
    "?d=wavatar&s=128";
};

var selectCommit = function (a) {
  gitxBridge.post("selectCommit", { sha: a });
};

var updateCommitRefs = function (commitData) {
  if (!commit) return;
  if (commitData && commitData.sha && commitData.sha !== commit.sha) return;
  commit.updateFromData(commitData || {});
  showRefs();
};

// Relead only refs
var reload = function (payload) {
  document.getElementById("notification").style.display = "none";
  if (payload) updateCommitRefs(payload);
  else if (commit) showRefs();
};

var showRefs = function () {
  var refs = document.getElementById("refs");
  if (commit && commit.refs && commit.refs.length) {
    refs.parentNode.style.display = "";
    refs.innerHTML = "";
    for (var i = 0; i < commit.refs.length; i++) {
      var ref = commit.refs[i] || {};
      var refName = (ref.ref || "").toString();
      var shortName =
        ref.shortName != null && ref.shortName !== ""
          ? ref.shortName
          : refName;
      shortName = shortName.toString();
      var cssType = (ref.type || "").toString();
      var span = document.createElement("span");
      span.className = "refs " + cssType + (commit.currentRef === refName && refName !== "" ? " currentBranch" : "");
      span.textContent = shortName;
      span.onclick = function () {
        var el = this;
        var originalText = el.textContent;
        copyToClipboard(originalText, null);
        el.textContent = "copied";
        setTimeout(function () {
          el.textContent = originalText;
        }, 1000);
      };
      refs.appendChild(span);
      refs.appendChild(document.createTextNode(" "));
    }
  } else refs.parentNode.style.display = "none";
};

var loadCommit = function (commitObject, currentRef) {
  // These are only the things we can do instantly.
  // Other information will be loaded later by loadCommitDetails,
  // Which will be called from the controller once
  // the commit details are in.

  if (commit && commit.notificationID) clearTimeout(commit.notificationID);

  commit = new Commit(commitObject);
  commit.fullyLoaded = false;
  if (typeof currentRef !== "undefined" && currentRef !== null)
    commit.currentRef = currentRef;

  document.getElementById("commitID").textContent = commit.sha;
  document.getElementById("authorID").textContent = commit.author_name;
  document.getElementById("subjectID").innerHTML = commit.subject.toString().escapeHTML();
  document.getElementById("diff").innerHTML = "";
  document.getElementById("message").innerHTML = "";
  document.getElementById("files").innerHTML = "";
  document.getElementById("date").innerHTML = "";
  showRefs();

  // Show/hide GitHub URL button based on availability
  var ghButton = document.getElementById("copyGitHubUrlButton");
  if (ghButton) {
    ghButton.style.display = commit.gitHubUrl ? "" : "none";
  }

  for (
    var i = 0;
    i < document.getElementById("commit_header").rows.length;
    ++i
  ) {
    var row = document.getElementById("commit_header").rows[i];
    if (row.innerHTML.match(/Parent:/)) {
      row.parentNode.removeChild(row);
      --i;
    }
  }

  // Scroll to top
  scroll(0, 0);

  if (!commit.parents || !commit.parents.length) return;

  for (var i = 0; i < commit.parents.length; i++) {
    var parentSha = (commit.parents[i] || "").toString();
    var newRow = document.getElementById("commit_header").insertRow(-1);
    newRow.innerHTML =
      "<td class='property_name'>Parent:</td><td>" +
      "<a class=\"SHA\" href='' onclick='selectCommit(this.innerHTML); return false;'>" +
      parentSha.escapeHTML() +
      "</a></td>";
  }

  commit.notificationID = setTimeout(function () {
    if (!commit.fullyLoaded) notify("Loading commit…", 0);
    commit.notificationID = null;
  }, 500);
};

var commonPrefix = function (a, b) {
  if (a === b) return a;
  var i = 0;
  while (a.charAt(i) == b.charAt(i)) ++i;
  return a.substring(0, i);
};
var commonSuffix = function (a, b) {
  if (a === b) return "";
  var i = a.length - 1,
    k = b.length - 1;
  while (a.charAt(i) == b.charAt(k)) {
    --i;
    --k;
  }
  return a.substring(i + 1, a.length);
};
var renameDiff = function (a, b) {
  var p = commonPrefix(a, b),
    s = commonSuffix(a, b),
    o = a.substring(p.length, a.length - s.length),
    n = b.substring(p.length, b.length - s.length);
  return [p, o, n, s];
};
var formatRenameDiff = function (d) {
  var p = d[0],
    o = d[1],
    n = d[2],
    s = d[3];
  if (o === "" && n === "" && s === "") {
    return p;
  }
  return [p, "{ ", o, " → ", n, " }", s].join("");
};

// Pending file entries waiting for autogenerated check
var pendingFileEntries = null;
var pendingCommitSha = null;

// Sort and reorder files based on autogenerated status
var sortAndReorderFiles = function (autogeneratedList) {
  if (!pendingFileEntries) return;

  var filesElement = document.getElementById("files");
  var diffElement = document.getElementById("diff");
  var autogenSet = {};
  for (var i = 0; i < autogeneratedList.length; i++) {
    autogenSet[autogeneratedList[i]] = true;
  }

  // Mark autogenerated status
  for (var i = 0; i < pendingFileEntries.length; i++) {
    var entry = pendingFileEntries[i];
    entry.isAutogenerated = !!autogenSet[entry.filename];
  }

  // Sort: non-autogenerated first, then autogenerated
  pendingFileEntries.sort(function (a, b) {
    if (a.isAutogenerated === b.isAutogenerated) return 0;
    return a.isAutogenerated ? 1 : -1;
  });

  // Clear and re-append file list entries in sorted order
  filesElement.innerHTML = "";
  for (var i = 0; i < pendingFileEntries.length; i++) {
    filesElement.appendChild(pendingFileEntries[i].element);
  }

  // Also reorder the diff sections to match
  var diffChildren = [];
  for (var i = 0; i < pendingFileEntries.length; i++) {
    var fileDiv = document.getElementById(pendingFileEntries[i].id);
    if (fileDiv) {
      // Also grab the following top-link div if present
      var topLink = fileDiv.nextElementSibling;
      diffChildren.push({ file: fileDiv, topLink: topLink && topLink.classList.contains("top-link") ? topLink : null });
    }
  }

  // Reorder diff sections
  for (var i = 0; i < diffChildren.length; i++) {
    diffElement.appendChild(diffChildren[i].file);
    if (diffChildren[i].topLink) {
      diffElement.appendChild(diffChildren[i].topLink);
    }
  }
};

var showDiff = function () {
  var filesElement = document.getElementById("files");
  var diffElement = document.getElementById("diff");
  filesElement.innerHTML = "";

  // Collect file entries for sorting
  var fileEntries = [];
  var fileNames = [];
  var rawDiff = commit.diff || "";

  // Callback for the diff highlighter. Used to generate a filelist
  var newfile = function (name1, name2, id, mode_change, old_mode, new_mode) {
    var img = document.createElement("img");
    var p = document.createElement("p");
    var link = document.createElement("a");
    link.setAttribute("href", "#" + id);
    p.appendChild(link);
    var finalFile = "";
    var renamed = false;
    if (name1 == name2) {
      finalFile = name1;
      img.src = "../../images/modified.svg";
      if (mode_change)
        p.appendChild(
          document.createTextNode(" mode " + old_mode + " → " + new_mode)
        );
    } else if (name1 == "/dev/null") {
      img.src = "../../images/added.svg";
      img.title = "Added file";
      p.title = "Added file";
      finalFile = name2;
    } else if (name2 == "/dev/null") {
      img.src = "../../images/removed.svg";
      img.title = "Removed file";
      p.title = "Removed file";
      finalFile = name1;
    } else {
      renamed = true;
    }
    if (renamed) {
      img.src = "../../images/renamed.svg";
      img.title = "Renamed file";
      p.title = "Renamed file";
      finalFile = name2;
      var rfd = renameDiff(name1.unEscapeHTML(), name2.unEscapeHTML());
      var html = [
        '<span class="renamed">',
        rfd[0].escapeHTML(),
        '<span class="meta"> { </span>',
        '<span class="old">',
        rfd[1].escapeHTML(),
        "</span>",
        '<span class="meta"> -&gt; </span>',
        '<span class="new">',
        rfd[2].escapeHTML(),
        "</span>",
        '<span class="meta"> } </span>',
        rfd[3].escapeHTML(),
        "</span>",
      ].join("");
      link.innerHTML = html;
    } else {
      link.appendChild(document.createTextNode(finalFile.unEscapeHTML()));
    }
    link.setAttribute("representedFile", finalFile);

    p.insertBefore(img, link);
    p.setAttribute("data-file-id", id);

    var checkFilename = (finalFile || name2 || name1 || "").replace(/^\/?/, "");
    fileEntries.push({ element: p, id: id, filename: checkFilename, isAutogenerated: false });

    // Don't include deleted files in the check (they don't exist at this commit)
    if (name2 !== "/dev/null") {
      fileNames.push(checkFilename);
    }
  };

  var binaryDiff = function (filename) {
    if (filename.match(/\.(png|jpg|icns|psd)$/i))
      return (
        '<a href="#" onclick="return showImage(this, \'' +
        filename +
        "')\">Display image</a>"
      );
    else return "Binary file differs";
  };

  highlightDiff(rawDiff, diffElement, {
    newfile: newfile,
    binaryFile: binaryDiff,
  });

  // Initially append files in original order
  for (var i = 0; i < fileEntries.length; i++) {
    filesElement.appendChild(fileEntries[i].element);
  }

  // Store for async callback
  pendingFileEntries = fileEntries;
  pendingCommitSha = commit.sha;

  // Request autogenerated file check from native side
  if (fileNames.length > 0 && commit.sha) {
    gitxBridge.post("checkAutogeneratedFiles", {
      sha: commit.sha,
      files: fileNames
    });
  }
};

var showImage = function (element, filename) {
  element.outerHTML = '<img src="GitX://' + commit.sha + "/" + filename + '">';
  return false;
};


var loadCommitDetails = function (data) {
  if (!commit) return;
  commit.parseDetails(data);

  if (commit.notificationID) clearTimeout(commit.notificationID);
  else document.getElementById("notification").style.display = "none";

  var formatEmail = function (name, email) {
    return email
      ? name + " &lt;" + email + "&gt;"
      : name;
  };

  var formatDate = function (date) {
    if (!date) return "";
    var now = new Date();
    var isToday = date.getFullYear() === now.getFullYear() &&
                  date.getMonth() === now.getMonth() &&
                  date.getDate() === now.getDate();
    var isCurrentYear = date.getFullYear() === now.getFullYear();

    // Format time as h:MMam/pm
    var hours = date.getHours();
    var ampm = hours >= 12 ? "pm" : "am";
    hours = hours % 12;
    if (hours === 0) hours = 12;
    var minutes = date.getMinutes().toString().padStart(2, "0");
    var time = hours + ":" + minutes + ampm;

    if (isToday) {
      return time;
    }

    var month = date.getMonth() + 1;
    var day = date.getDate();
    var year = date.getFullYear() % 100;

    if (isCurrentYear) {
      return month + "/" + day + ", " + time;
    }

    return month + "/" + day + "/" + year + ", " + time;
  };

  document.getElementById("authorID").innerHTML = formatEmail(
    commit.author_name,
    commit.author_email
  );
  document.getElementById("date").innerHTML = formatDate(commit.author_date);
  setGravatar(commit.author_email, document.getElementById("author_gravatar"));

  if (commit.committer_name != commit.author_name) {
    document.getElementById("committerID").parentNode.style.display = "";
    document.getElementById("committerID").innerHTML = formatEmail(
      commit.committer_name,
      commit.committer_email
    );

    document.getElementById("committerDate").parentNode.style.display = "";
    document.getElementById("committerDate").innerHTML = formatDate(commit.committer_date);
  } else {
    document.getElementById("committerID").parentNode.style.display = "none";
    document.getElementById("committerDate").parentNode.style.display = "none";
  }

  document.getElementById("message").innerHTML = commit.message
    .replace(/\b(https?:\/\/[^\s<]*)/gi, '<a href="$1">$1</a>')
    .replace(/\n/g, "<br>");

  if (commit.diff.length < 200000) showDiff();
  else
    document.getElementById("diff").innerHTML =
      "<a class='showdiff' href='' onclick='showDiff(); return false;'>This is a large commit. Click here or press 'v' to view.</a>";

  hideNotification();
  commit.fullyLoaded = true;
};

var handleNativeMessage = function (message) {
  if (!message || typeof message.type !== "string") return;
  switch (message.type) {
    case "commitSelected":
      loadCommit(message.commit || {}, message.currentRef);
      break;
    case "commitRefsUpdated":
      updateCommitRefs(message.commit || {});
      break;
    case "commitDetails":
      if (!commit) return;
      if (message.sha && message.sha !== commit.sha) return;
      if (typeof message.details === "string") {
        loadCommitDetails(message.details);
      }
      break;
    case "autogeneratedFilesResult":
      // Only process if this is for the current commit
      if (message.sha && message.sha === pendingCommitSha && pendingFileEntries) {
        var autogenerated = message.autogenerated;
        if (autogenerated && autogenerated.length > 0) {
          sortAndReorderFiles(autogenerated);
        }
      }
      break;
    case "historyKeyCommand":
      if (typeof handleKeyFromCocoa === "function") {
        try {
          handleKeyFromCocoa(message.key);
        } catch (error) {
          if (window.console && console.error) {
            console.error("historyKeyCommand handler failed", error);
          }
        }
      }
      break;
  }
};

gitxBridge.subscribe(handleNativeMessage);

var copyShaToClipboard = function () {
  var shaElement = document.getElementById("commitID");
  if (!shaElement) return;

  var sha = shaElement.textContent;
  if (!sha) return;

  var button = document.getElementById("copyShaButton");
  var originalText = button ? button.textContent : null;

  var showCopied = function () {
    if (!button) return;
    button.textContent = "copied";
    setTimeout(function () {
      button.textContent = originalText;
    }, 1000);
  };

  var fallbackCopy = function () {
    try {
      var tempInput = document.createElement("textarea");
      tempInput.value = sha;
      tempInput.setAttribute("readonly", "");
      tempInput.style.position = "fixed";
      tempInput.style.top = "0";
      tempInput.style.left = "-9999px";
      tempInput.style.opacity = "0";
      document.body.appendChild(tempInput);
      tempInput.select();
      tempInput.setSelectionRange(0, tempInput.value.length);
      var copied = document.execCommand("copy");
      document.body.removeChild(tempInput);
      if (copied) {
        showCopied();
      }
    } catch (error) {
      console.error("Failed to copy SHA to clipboard:", error);
    }
  };

  if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
    navigator.clipboard
      .writeText(sha)
      .then(showCopied)
      .catch(function (error) {
        console.error("navigator.clipboard.writeText failed:", error);
        fallbackCopy();
      });
  } else {
    fallbackCopy();
  }
};

var copyToClipboard = function (text, button) {
  if (!text) return;

  var originalText = button ? button.textContent : null;

  var showCopied = function () {
    if (!button) return;
    button.textContent = "copied";
    setTimeout(function () {
      button.textContent = originalText;
    }, 1000);
  };

  var fallbackCopy = function () {
    try {
      var tempInput = document.createElement("textarea");
      tempInput.value = text;
      tempInput.setAttribute("readonly", "");
      tempInput.style.position = "fixed";
      tempInput.style.top = "0";
      tempInput.style.left = "-9999px";
      tempInput.style.opacity = "0";
      document.body.appendChild(tempInput);
      tempInput.select();
      tempInput.setSelectionRange(0, tempInput.value.length);
      var copied = document.execCommand("copy");
      document.body.removeChild(tempInput);
      if (copied) {
        showCopied();
      }
    } catch (error) {
      console.error("Failed to copy to clipboard:", error);
    }
  };

  if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
    navigator.clipboard
      .writeText(text)
      .then(showCopied)
      .catch(function (error) {
        console.error("navigator.clipboard.writeText failed:", error);
        fallbackCopy();
      });
  } else {
    fallbackCopy();
  }
};

var copyShortShaToClipboard = function () {
  if (!commit || !commit.shortSha) return;
  var button = document.getElementById("copyShortShaButton");
  copyToClipboard(commit.shortSha, button);
};

var copyGitHubUrlToClipboard = function () {
  if (!commit || !commit.gitHubUrl) return;
  var button = document.getElementById("copyGitHubUrlButton");
  copyToClipboard(commit.gitHubUrl, button);
};
