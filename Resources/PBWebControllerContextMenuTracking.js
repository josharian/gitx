(function () {
  var gitx = (window.gitx = window.gitx || {});
  gitx._lastContextMenuInfo = gitx._lastContextMenuInfo || {};
  gitx.getLastContextMenuInfo = function () {
    return gitx._lastContextMenuInfo || {};
  };
  function extractInfo(target) {
    var info = { type: 'default' };
    var node = target;
    while (node) {
      if (
        !info.refText &&
        node.className &&
        typeof node.className === 'string' &&
        node.className.indexOf('refs ') === 0
      ) {
        info.type = 'refs';
        info.refText = (node.textContent || '').trim();
        break;
      }
      if (node.hasAttribute && node.hasAttribute('representedFile')) {
        info.type = 'representedFile';
        info.representedFile = node.getAttribute('representedFile') || '1';
        break;
      }
      if (node.tagName && node.tagName.toUpperCase() === 'IMG') {
        info.type = 'image';
        break;
      }
      node = node.parentNode;
    }
    return info;
  }
  function handleContextMenu(event) {
    try {
      var info = extractInfo(event.target || event.srcElement);
      gitx._lastContextMenuInfo = info;
      if (gitx.postMessage) {
        gitx.postMessage({ type: '__contextMenuPreview__', info: info });
      }
    } catch (error) {
      if (window.console && console.error) {
        console.error('gitx context menu tracking failed', error);
      }
    }
  }
  if (document && document.addEventListener) {
    document.addEventListener('contextmenu', handleContextMenu, true);
  }
})();
