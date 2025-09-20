window.gitxNativePost = window.gitxNativePost || function (payload) {
  try {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.gitxBridge) {
      window.webkit.messageHandlers.gitxBridge.postMessage(payload || {});
    }
  } catch (error) {
    if (window.console && console.error) {
      console.error('gitxNativePost failed', error);
    }
  }
};
