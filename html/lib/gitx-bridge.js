(function(global) {
  'use strict';

  var consoleRef = global.console || {};
  var noop = function() {};
  var errorLogger = typeof consoleRef.error === 'function' ? consoleRef.error.bind(consoleRef) : noop;

  function clonePayload(payload) {
    var message = {};
    if (!payload || typeof payload !== 'object') {
      return message;
    }
    for (var key in payload) {
      if (Object.prototype.hasOwnProperty.call(payload, key) && key !== 'type') {
        message[key] = payload[key];
      }
    }
    return message;
  }

  function post(type, payload, fallback) {
    if (typeof type !== 'string' || type.length === 0) {
      if (typeof fallback === 'function') {
        try { fallback(); } catch (error) { errorLogger('gitxBridge fallback failed', error); }
      }
      return false;
    }

    var message = clonePayload(payload);
    message.type = type;

    var gitx = global.gitx;
    if (gitx && typeof gitx.postMessage === 'function') {
      try {
        gitx.postMessage(message);
        return true;
      } catch (error) {
        errorLogger('gitxBridge post failed', error, message);
      }
    }

    if (typeof fallback === 'function') {
      try {
        fallback();
      } catch (fallbackError) {
        errorLogger('gitxBridge fallback failed', fallbackError);
      }
    }
    return false;
  }

  function subscribe(handler) {
    if (typeof handler !== 'function') {
      return noop;
    }

    var gitx = global.gitx = global.gitx || {};

    if (typeof gitx.subscribeToNativeMessages === 'function') {
      return gitx.subscribeToNativeMessages(handler);
    }

    if (!gitx._bridgeLegacySubscribers) {
      gitx._bridgeLegacySubscribers = [];
      var previous = gitx.onNativeMessage;
      gitx.onNativeMessage = function(message) {
        if (typeof previous === 'function') {
          try {
            previous(message);
          } catch (error) {
            errorLogger('gitxBridge legacy previous handler failed', error);
          }
        }
        var subscribers = gitx._bridgeLegacySubscribers.slice();
        for (var i = 0; i < subscribers.length; i++) {
          var subscriber = subscribers[i];
          try {
            subscriber(message);
          } catch (subscriberError) {
            errorLogger('gitxBridge legacy handler failed', subscriberError);
          }
        }
      };
    }

    gitx._bridgeLegacySubscribers.push(handler);
    return function unsubscribe() {
      if (!gitx._bridgeLegacySubscribers) {
        return;
      }
      for (var i = gitx._bridgeLegacySubscribers.length - 1; i >= 0; i--) {
        if (gitx._bridgeLegacySubscribers[i] === handler) {
          gitx._bridgeLegacySubscribers.splice(i, 1);
        }
      }
    };
  }

  global.gitxBridge = {
    post: post,
    subscribe: subscribe
  };
})(window);
