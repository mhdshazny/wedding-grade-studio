{{flutter_js}}
{{flutter_build_config}}

// Serve CanvasKit from the app's own origin so the app is fully
// self-contained (no CDN dependency).
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
