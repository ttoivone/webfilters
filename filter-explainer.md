Web Video Filter API
====================

**Authors:** *Rijubrata Bhaumik <rijubrata.bhaumik@intel.com>*,
*Tuukka Toivonen <tuukka.toivonen@intel.com>*

# Background and Problem Statement

Video is nowadays ubiquitous on the web platform. In all cases, there are operations which are
applied to the video between video producer and consumer. If not else, the video is at least
captured into digital form, compressed to save bandwidth, and decompressed at the receiver end.
These operations degrade the video quality and new operations, filters, have been developed
to restore the video quality or to enhance the video for the consumer's delight. Examples of
commonly used video filters include:

* Removing noise
* Removing compression artifacts
* Scaling image down or up (superresolution)
* Enhancing color and contrast
* Background concealment (in video conferencing)
* Frame temporal interpolation for smoother playback

Due to a large amount of data involved and the nature of many filters, video filtering
generally demands a large amount of computation. While computers have become more
powerful, so have video filters, and many video filters can be expected to continue
being very power-intensive.

Highly optimized software and hardware have been developed in order to reduce the
power required for video filtering. This is particularly important in mobile
applications, operating on battery power. However, web applications are not able
to take advantage of these efficient filters, but need to rely on WASM-based
implementations with a loss in efficiency.

# The Proposed Approach

Relatively recently the [WebCodecs API](https://www.w3.org/TR/webcodecs/) brought
efficient system-provided video encoders and decoders into web applications. In
this explainer, we propose a new API to make the commonly used video filters available
for web applications as well. In particular, we propose reusing the
[`VideoFrame`](https://w3c.github.io/webcodecs/#videoframe) interface in video
applications needing video filtering.

Similarly to how WebCodecs allows calling system-level video encoders and decoders,
we make available the system-level video filters.

## Goals

* **Filter capabilities**: Make some generic assumptions on video filters, such as:
  * They may modify the resolution of frames (scale or crop);
  * They may modify the frame rate of a video;
  * They may have multiple inputs and outputs.
* **Base API**: Define WebCodecs (`VideoFrame`) -based API which allows utilizing system-level
  video filters efficiently and allows users to configure the generic part of filters.
* **Filter set**: Define a set of filters which are both commonly used or needed and provided by
  many systems; specialize the generic API to each of the specific filter with
  minimal changes.
* **Extensibility**: Make the API extensible so that new filters can be easily defined and added
  to the defined API in a backwards-compatible way.
* The API must also allow users to query the set of available filters.

## Non-goals

* Web applications do not need to allow providing filters themselves
  (although a polyfill-style approach may be feasible). These (eg. WASM-based)
  filters might have lower performance. User should be able to trust the
  efficient implementation of the provided filters.
* Other data content except video frames/video. Although audio filters
  might be useful, their performance is usually sufficient also with
  an efficient WASM-based implementation. We also do not consider more
  exotic data content (eg. vector-based meshes) since that would complicate
  the API and has limited support on common systems.
* A filter can be configured only once. If configuration needs to be changed,
  the filter needs to be destructed and a new filter needs to be created. Static
  configuration includes the number of input and output streams and frame resolution
  on each stream.

# The Video Filtering API

The `VideoFilter` interface is a mix of the existing
[`VideoDecoder`](https://w3c.github.io/webcodecs/#videodecoder-interface) and
[`VideoEncoder`](https://w3c.github.io/webcodecs/#videoencoder-interface)
interfaces. It inputs and outputs `VideoFrame`s, not necessarily to 1:1, and processes
them as configured.

```
[Exposed=(Window,DedicatedWorker), SecureContext]
interface VideoFilter {
  constructor(VideoFilterInit init);

  readonly attribute FilterState state;
  readonly attribute unsigned long filterQueueSize;

  undefined configure(VideoFilterConfig config);
  undefined filter(VideoFrame frame);
  Promise<undefined> flush();
  undefined reset();
  undefined close();

  static Promise<VideoFilterSupport> isConfigSupported(VideoFilterConfig config);
};
```

The `VideoFilter` is constructed using the `VideoFilterInit` dictionary. It holds
two fields where the
[WebCodecsErrorCallback](https://w3c.github.io/webcodecs/#callbackdef-webcodecserrorcallback)
is defined in the WebCodecs specification.

```
dictionary VideoFilterInit {
  required VideoFilterOutputCallback output;
  required WebCodecsErrorCallback error;
};
```

After creation, the VideoFilter is in the `unconfigured` state and needs to be
configured by specifying the desired filter.

```
enum FilterState {
  "unconfigured",
  "configured",
  "closed"
};
```

`VideoFilterConfig` defines which video filter is needed and its configuration.

```
dictionary VideoFilterConfig {
  required DOMString filter;
  [EnforceRange] unsigned long codedWidth;
  [EnforceRange] unsigned long codedHeight;
  [EnforceRange] unsigned long displayAspectWidth;
  [EnforceRange] unsigned long displayAspectHeight;
  VideoColorSpaceInit colorSpace;
  HardwareAcceleration hardwareAcceleration = "no-preference";
  boolean optimizeForLatency;
};
```

`VideoFilterConfig` is the base dictionary which contains the fields common
to all video filters. The first field `filter` is the name of the filter to be
used. The frame resolution is defined similarly as in the WebCodecs API using
the following four fields for input `VideoFrame`s. The remaining three fields
(`colorSpace`, `hardwareAcceleration`, and `optimizeForLatency`) have also
the same significance as in the [WebCodecs specification](https://w3c.github.io/webcodecs/#videoframe).

In general, ``VideoFilterConfig`` is not directly passed to any method but some
of the dictionaries which inherit from it. A simple example could be denoising filter, where the
inheriting dictionary might contain only a single additional member, the filter strength:

```
// When filter == "denoising"
dictionary VideoFilterDenoisingConfig : VideoFilterConfig {
  float strength;
};
```

Instead of configuring immediately the filter after construction, user should
negotiate a supported filter configuration by initializing one of the dictionaries
which inherit from `VideoFilterConfig` and passing it to `isConfigSupported`.
The returned promise contains the same dictionary modified so that it contains
the parameters for the requested filter as close as requested and supported by the system,
or if the filter is not supported at all, `supported` field will be set to ``false``.

```
dictionary VideoFilterSupport {
  boolean supported;
  VideoFilterConfig config;
};
```

If the `supported` field is `true`, the returned filter parameters are guaranteed
to be supported and can be provided to method `configure` which configures the filter
(field `state` is set to `configured`).

A new frame is filtered by passing it to the method `filter`. The frame resolution
must match what was configured. Several frames can be queued, and in some cases, must
be queued (eg. temporal filtering) before any filtered frame is returned.
The field `filterQueueSize` contains the number of pending filtering requests.
The argument `stream_in` denotes the input stream number; for common filters with
just a single input stream it must be always zero.

When a newly filtered frame is available, it is given to the callback `output`
of type `VideoFilterOutputCallback`. Unless the filter produces multiple output
streams, the `stream_out` argument shall be zero.

```
callback VideoFilterOutputCallback = undefined(VideoFrame frame, unsigned short stream_out);

```

# Platform Support

This sections lists some filters available on different platforms
and APIs available for users. The exact parameters and features of
filters between the platforms and APIs vary, and the table may also
have errors and omissions.

| Filter                                | W | L | M | v | d | m | c |
|:--------------------------------------|:--|:--|:--|:--|:--|:--|:--|
| Brightness, Contrast, Hue, Saturation |   | X | X | X |   | X | X |
| White balance                         |   | X | X | X |   | X | X |
| Color space conversion                |   | X | X | X |   | X | X |
| Denoise                               |   | X | X | X |   | X | X |
| Scaling                               | X | X |   | X | X | X |   |
| Deinterlace                           | X | X |   |   | X | X |   |
| Blur                                  |   |   | X |   |   |   | X |
| Sharpen                               |   | X | X | X |   | X | X |
| Transpose/rotation                    |   | X |   |   |   | X |   |
| Image blending                        | X |   |   |   | X |   |   |
| Video composition                     |   | X |   |   |   | X |   |
| Video stabilization                   |   |   |   |   |   | X |   |
| Skin color enhancement                |   |   |   |   |   | X |   |
| Gamma correction                      |   |   | X |   |   | X | X |

Where

* W: Windows
* L: Linux
* M: MacOS
* v: [VA-API](http://intel.github.io/libva/group__api__vpp.html) with [GStreamer](https://gstreamer.freedesktop.org/documentation/vaapi/vaapipostproc.html?gi-language=c#vaapipostproc) on Linux
* d: Microsoft [Media Foundation/DXVA](https://docs.microsoft.com/en-us/windows-hardware/drivers/ddi/dxva/) on Windows
* m: Intel [MediaSDK](https://github.com/Intel-Media-SDK/MediaSDK/blob/master/doc/samples/readme-vpp_linux.md) on Linux
* c: Apple [Core Image Filter](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html#//apple_ref/doc/uid/TP40004346) on MacOS

# Examples

## Example 1: Simple Denoising

```
VideoFilterInit filterInit = {
  output: outputCallback,
  error: errorCallback
};
filter = new VideoFilter(filterInit);

config = {
  filter: 'denoising',
  codedWidth: 640,
  codedHeight: 480,
  strength: 0.5
};

filterSupport = await filter.isConfigSupported(config);
if (!filterSupport.supported) {
  // Not supported, must skip filtering
  // or use WASM-based implementation
}

filter.configure(filterSupport.config);

const canvas = document.getElementById('myCanvas');
const context = canvas.getContext('2d');
const track = stream.getVideoTracks()[0];
const media_processor = new MediaStreamTrackProcessor(track);
const reader = media_processor.readable.getReader();
while (true) {
  const result = await reader.read();
  if (result.done)
    break;
  let frame = result.value;
  if (filter.filterQueueSize < 3) {
    // Drop the frame if the filter struggles to process them all
    filter.filter(frame, 0);
  }
  frame.close();
}

function outputCallback(frame, stream_out) {
  if (stream_out != 0)
    return;
  context.drawImage(frame, 0, 0);
  frame.close();
}

function errorCallback(DOMException error) {
  // Error occurred    
}
```

# Rationale

* We decided to define frame resolution during filter configuration time
  using four fields (`codedWidth`, `codedHeight`, `displayAspectWidth`, `displayAspectHeight`).
  In some systems filters have a requirement to have some padding pixels around the
  visible frame pixels, in particularly with odd resolutions, and using four fields
  allows this.
* Although each input `VideoFrame` to a filter specifies also the frame resolution,
  requiring user to define resolution during configuration time allows negotiating
  for valid frame resolution in advance and possibly in parallel with other
  processing such as establising connections, speeding up application startup time.

# Security and Privacy Implications 

Security and privacy implications are similar to WebCodecs codecs. The user agent
should provide access only to those system filters which offer reasonably guarantee on
security and privacy. The system should not have undesired behaviour no matter what
input data (video) is fed into the system video filter. The system API should also
guarantee that the privacy of the processed data is maintained or else the user agent
should not make the API available to web applications.

# Acknowledgments

Many thanks for valuable feedback and advice from:

* Eero Hakkinen
* Ben Lin
* Jianlin Qiu

