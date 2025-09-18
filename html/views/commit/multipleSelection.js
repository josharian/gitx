var showMultipleFilesSelection = function(files)
{
	hideNotification();
	setTitle("");

	var div = document.getElementById("diff");

	var contents = '<div id="multiselect">' +
		'<div class="title">Multiple Selection</div>';

	contents += "<ul>";

	for (var i = 0; i < files.length; ++i)
	{
		var file = files[i];
		var path = "";
		if (typeof file === "string")
			path = file;
		else if (file && typeof file.path === "string")
			path = file.path;
		else if (file && file.path && typeof file.path === "function")
			path = file.path();
		contents += "<li>" + path.toString().escapeHTML() + "</li>";
	}
	contents += "</ul></div>";

	div.innerHTML = contents;
	div.style.display = "";
}
