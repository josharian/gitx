(function () {
  var gitx = (window.gitx = window.gitx || {});
  gitx._nativeSubscribers = gitx._nativeSubscribers || [];
  gitx.postMessage =
    gitx.postMessage ||
    function (payload) {
      try {
        window.gitxNativePost(payload || {});
      } catch (error) {
        if (window.console && console.error) {
          console.error('gitx.postMessage failed', error);
        }
      }
    };
  gitx.subscribeToNativeMessages =
    gitx.subscribeToNativeMessages ||
    function (handler) {
      if (typeof handler !== 'function') {
        return function () {};
      }
      gitx._nativeSubscribers.push(handler);
      return function () {
        var index = gitx._nativeSubscribers.indexOf(handler);
        if (index >= 0) {
          gitx._nativeSubscribers.splice(index, 1);
        }
      };
    };
  gitx._dispatchNativeMessage = function (message) {
    var payload = message;
    if (typeof message === 'string') {
      try {
        payload = JSON.parse(message);
      } catch (error) {
        if (window.console && console.error) {
          console.error('gitx._dispatchNativeMessage parse failure', error, message);
        }
        return;
      }
    }
    if (!payload || typeof payload !== 'object') {
      return;
    }
    if (typeof gitx.onNativeMessage === 'function') {
      try {
        gitx.onNativeMessage(payload);
      } catch (error) {
        if (window.console && console.error) {
          console.error('gitx.onNativeMessage failure', error);
        }
      }
    }
    gitx._nativeSubscribers.slice().forEach(function (handler) {
      try {
        handler(payload);
      } catch (error) {
        if (window.console && console.error) {
          console.error('gitx native subscriber failure', error);
        }
      }
    });
  };
  window.gitxReceiveNativeMessage = gitx._dispatchNativeMessage;
  if (window.gitxBridge && typeof window.gitxBridge.flush === 'function') {
    try {
      window.gitxBridge.flush();
    } catch (error) {
      if (window.console && console.error) {
        console.error('gitxBridge.flush failed', error);
      }
    }
  }
})();
