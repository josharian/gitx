var commit;

// Create a new Commit object
// obj: PBGitCommit object
var Commit = function (obj) {
  this.object = obj;

  this.refs = obj.refs();
  this.author_name = obj.author();
  this.committer_name = obj.committer();
  this.sha = obj.realSha();
  this.parents = obj.parents();
  this.subject = obj.subject();
  this.notificationID = null;

  // TODO:
  // this.author_date instant

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
          this.author_date = new Date(parseInt(match[3]) * 1000);

        match = this.header.match(/\ncommitter (.*) <(.*@.*|.*)> ([0-9].*)/);
        if (typeof match[2] !== "undefined") this.committer_email = match[2];
        if (typeof match[3] !== "undefined")
          this.committer_date = new Date(parseInt(match[3]) * 1000);
      }
    }
  };

  this.reloadRefs = function () {
    this.refs = this.object.refs();
  };
};

var setGravatar = function (email, image) {
  if (Controller && !Controller.isFeatureEnabled_("gravatar")) {
    image.src = "";
    return;
  }

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
  Controller.selectCommit_(a);
};

// Relead only refs
var reload = function () {
  document.getElementById("notification").style.display = "none";
  commit.reloadRefs();
  showRefs();
};

var showRefs = function () {
  var refs = document.getElementById("refs");
  if (commit.refs) {
    refs.parentNode.style.display = "";
    refs.innerHTML = "";
    for (var i = 0; i < commit.refs.length; i++) {
      var ref = commit.refs[i];
      refs.innerHTML +=
        '<span class="refs ' +
        ref.type() +
        (commit.currentRef == ref.ref ? " currentBranch" : "") +
        '">' +
        ref.shortName() +
        "</span> ";
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
  commit.currentRef = currentRef;

  document.getElementById("commitID").innerHTML = commit.sha;
  document.getElementById("authorID").innerHTML = commit.author_name;
  document.getElementById("subjectID").innerHTML = commit.subject.escapeHTML();
  document.getElementById("diff").innerHTML = "";
  document.getElementById("message").innerHTML = "";
  document.getElementById("files").innerHTML = "";
  document.getElementById("date").innerHTML = "";
  showRefs();

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

  if (!commit.parents) return;

  for (var i = 0; i < commit.parents.length; i++) {
    var newRow = document.getElementById("commit_header").insertRow(-1);
    newRow.innerHTML =
      "<td class='property_name'>Parent:</td><td>" +
      "<a class=\"SHA\" href='' onclick='selectCommit(this.innerHTML); return false;'>" +
      commit.parents[i].SHA() +
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

var showDiff = function () {
  document.getElementById("files").innerHTML = "";

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
      img.title = "Modified file";
      p.title = "Modified file";
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
    document.getElementById("files").appendChild(p);
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

  highlightDiff(commit.diff, document.getElementById("diff"), {
    newfile: newfile,
    binaryFile: binaryDiff,
  });
};

var showImage = function (element, filename) {
  element.outerHTML = '<img src="GitX://' + commit.sha + "/" + filename + '">';
  return false;
};

var enableFeature = function (feature, element) {
  if (!Controller || Controller.isFeatureEnabled_(feature)) {
    element.style.display = "";
  } else {
    element.style.display = "none";
  }
};

var enableFeatures = function () {
  enableFeature(
    "gravatar",
    document.getElementById("author_gravatar").parentNode
  );
  enableFeature(
    "gravatar",
    document.getElementById("committer_gravatar").parentNode
  );
};

var loadCommitDetails = function (data) {
  commit.parseDetails(data);

  if (commit.notificationID) clearTimeout(commit.notificationID);
  else document.getElementById("notification").style.display = "none";

  var formatEmail = function (name, email) {
    return email
      ? name + " &lt;<a href='mailto:" + email + "'>" + email + "</a>&gt;"
      : name;
  };

  document.getElementById("authorID").innerHTML = formatEmail(
    commit.author_name,
    commit.author_email
  );
  document.getElementById("date").innerHTML = commit.author_date;
  setGravatar(commit.author_email, document.getElementById("author_gravatar"));

  if (commit.committer_name != commit.author_name) {
    document.getElementById("committerID").parentNode.style.display = "";
    document.getElementById("committerID").innerHTML = formatEmail(
      commit.committer_name,
      commit.committer_email
    );

    document.getElementById("committerDate").parentNode.style.display = "";
    document.getElementById("committerDate").innerHTML = commit.committer_date;
    setGravatar(
      commit.committer_email,
      document.getElementById("committer_gravatar")
    );
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
  enableFeatures();
};

var copyShaToClipboard = function () {
  var sha = document.getElementById("commitID").textContent;
  if (sha) {
    try {
      // Create a temporary input element to copy the SHA
      var tempInput = document.createElement("input");
      tempInput.style.position = "absolute";
      tempInput.style.left = "-1000px";
      tempInput.value = sha;
      document.body.appendChild(tempInput);
      tempInput.select();
      document.execCommand("copy");
      document.body.removeChild(tempInput);

      // Provide visual feedback
      var button = document.getElementById("copyShaButton");
      var originalText = button.textContent;
      button.textContent = "copied!";
      setTimeout(function () {
        button.textContent = originalText;
      }, 1000);
    } catch (e) {
      console.error("Failed to copy SHA to clipboard:", e);
    }
  }
};
