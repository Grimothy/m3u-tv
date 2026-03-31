import UIKit
import React
import MPVKit
import Metal

class MpvPlayerView: UIView {
    private var mpv: OpaquePointer?
    private var metalView: MPVMetalView?
    private var progressTimer: Timer?
    private var isInitialized = false
    private var pendingUri: String?
    private var pendingPaused = false
    private var pendingSeek: Double = -1

    // All mpv API calls run on this queue — keeps mpv off the main thread entirely
    private let mpvQueue = DispatchQueue(label: "mpv.core", qos: .userInteractive)

    // RN event callbacks — @objc + RCTDirectEventBlock so the bridge sets them via KVC
    @objc var onMpvLoad: RCTDirectEventBlock?
    @objc var onMpvProgress: RCTDirectEventBlock?
    @objc var onMpvBuffer: RCTDirectEventBlock?
    @objc var onMpvError: RCTDirectEventBlock?
    @objc var onMpvEnd: RCTDirectEventBlock?
    @objc var onMpvTracksChanged: RCTDirectEventBlock?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        setupMpv()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        setupMpv()
    }

    deinit {
        destroy()
    }

    private func setupMpv() {
        mpvQueue.async { [weak self] in
            guard let self else { return }

            guard let ctx = mpv_create() else { return }

            mpv_set_option_string(ctx, "hwdec", "videotoolbox-copy")
            mpv_set_option_string(ctx, "ao", "audiounit")
            mpv_set_option_string(ctx, "demuxer-max-bytes", "150MiB")
            mpv_set_option_string(ctx, "demuxer-max-back-bytes", "75MiB")
            mpv_set_option_string(ctx, "cache", "yes")
            mpv_set_option_string(ctx, "cache-secs", "120")
            mpv_set_option_string(ctx, "network-timeout", "30")
            mpv_set_option_string(ctx, "keep-open", "yes")
            mpv_set_option_string(ctx, "profile", "fast")
            mpv_set_option_string(ctx, "terminal", "no")
            mpv_set_option_string(ctx, "msg-level", "all=warn")
            mpv_set_option_string(ctx, "tls-verify", "no")
            mpv_set_option_string(ctx, "ytdl", "no")

            guard mpv_initialize(ctx) == 0 else {
                mpv_terminate_destroy(ctx)
                return
            }

            self.mpv = ctx

            mpv_observe_property(ctx, 0, "time-pos", MPV_FORMAT_DOUBLE)
            mpv_observe_property(ctx, 0, "duration", MPV_FORMAT_DOUBLE)
            mpv_observe_property(ctx, 0, "pause", MPV_FORMAT_FLAG)
            mpv_observe_property(ctx, 0, "paused-for-cache", MPV_FORMAT_FLAG)
            mpv_observe_property(ctx, 0, "track-list/count", MPV_FORMAT_INT64)
            mpv_observe_property(ctx, 0, "eof-reached", MPV_FORMAT_FLAG)

            // Wakeup fires on mpv's internal thread — dispatch to mpvQueue, not main,
            // to avoid competing with the render loop for the main thread.
            mpv_set_wakeup_callback(ctx, { ptr in
                guard let ptr else { return }
                let view = Unmanaged<MpvPlayerView>.fromOpaque(ptr).takeUnretainedValue()
                view.mpvQueue.async { view.handleEvents() }
            }, Unmanaged.passUnretained(self).toOpaque())

            // UIKit: create and attach the Metal view on main, then init render context on mpvQueue
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let mv = MPVMetalView(frame: self.bounds)
                mv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                self.addSubview(mv)
                self.metalView = mv

                self.mpvQueue.async { [weak self] in
                    // Re-read self.mpv — it may have been nil'd by destroy() before we got here
                    guard let self, let ctx = self.mpv else { return }
                    mv.initMpvRender(ctx)
                    self.isInitialized = true

                    if let uri = self.pendingUri {
                        self.doLoadFile(ctx, uri)
                        self.pendingUri = nil
                    }
                    if self.pendingPaused {
                        var flag: Int32 = 1
                        mpv_set_property(ctx, "pause", MPV_FORMAT_FLAG, &flag)
                    }

                    // Timer must be scheduled on a RunLoop thread — use main
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                            self?.mpvQueue.async { self?.emitProgress() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Public API (called from main thread by RN bridge; forwarded to mpvQueue)

    @objc func setUri(_ uri: String?) {
        guard let uri, !uri.isEmpty else { return }
        mpvQueue.async { [weak self] in
            guard let self else { return }
            if self.isInitialized, let ctx = self.mpv {
                self.doLoadFile(ctx, uri)
            } else {
                self.pendingUri = uri
            }
        }
    }

    @objc func setUserAgent(_ userAgent: String?) {
        guard let ua = userAgent else { return }
        mpvQueue.async { [weak self] in
            guard let ctx = self?.mpv else { return }
            mpv_set_option_string(ctx, "user-agent", ua)
        }
    }

    @objc func setPaused(_ paused: Bool) {
        mpvQueue.async { [weak self] in
            guard let self else { return }
            self.pendingPaused = paused
            guard let ctx = self.mpv, self.isInitialized else { return }
            var flag: Int32 = paused ? 1 : 0
            mpv_set_property(ctx, "pause", MPV_FORMAT_FLAG, &flag)
        }
    }

    @objc func setStartPosition(_ seconds: Double) {
        mpvQueue.async { [weak self] in
            if seconds > 0 { self?.pendingSeek = seconds }
        }
    }

    func seekTo(_ seconds: Double) {
        mpvQueue.async { [weak self] in
            guard let self, let ctx = self.mpv, self.isInitialized, seconds >= 0 else { return }
            self.doCommand(ctx, "seek", [seconds.description, "absolute"])
        }
    }

    func seekRelative(_ seconds: Double) {
        mpvQueue.async { [weak self] in
            guard let self, let ctx = self.mpv, self.isInitialized else { return }
            self.doCommand(ctx, "seek", [seconds.description, "relative"])
        }
    }

    func setAudioTrack(_ trackId: Int) {
        mpvQueue.async { [weak self] in
            guard let self, let ctx = self.mpv, self.isInitialized else { return }
            if trackId < 0 {
                mpv_set_option_string(ctx, "aid", "no")
            } else {
                var id = Int64(trackId)
                mpv_set_property(ctx, "aid", MPV_FORMAT_INT64, &id)
            }
        }
    }

    func setSubtitleTrack(_ trackId: Int) {
        mpvQueue.async { [weak self] in
            guard let self, let ctx = self.mpv, self.isInitialized else { return }
            if trackId < 0 {
                mpv_set_option_string(ctx, "sid", "no")
            } else {
                var id = Int64(trackId)
                mpv_set_property(ctx, "sid", MPV_FORMAT_INT64, &id)
            }
        }
    }

    func stop() {
        mpvQueue.async { [weak self] in
            guard let self, let ctx = self.mpv, self.isInitialized else { return }
            self.doCommand(ctx, "stop", [])
        }
    }

    func destroy() {
        // Use strong self throughout — [weak self] is nil by the time deinit calls destroy()
        // because Swift zeroes weak refs before deinit runs. Sync blocks have no retain-cycle risk.

        // 1. Stop timer (must be invalidated on the thread it was scheduled on — main)
        if Thread.isMainThread {
            progressTimer?.invalidate()
            progressTimer = nil
        } else {
            DispatchQueue.main.sync {
                self.progressTimer?.invalidate()
                self.progressTimer = nil
            }
        }

        // 2. Cleanup Metal view on main (cleanup() drains renderQueue.sync internally)
        if Thread.isMainThread {
            metalView?.cleanup()
            metalView?.removeFromSuperview()
            metalView = nil
        } else {
            DispatchQueue.main.sync {
                self.metalView?.cleanup()
                self.metalView?.removeFromSuperview()
                self.metalView = nil
            }
        }

        // 3. Tear down mpv on its queue
        mpvQueue.sync {
            if let ctx = self.mpv {
                mpv_set_wakeup_callback(ctx, nil, nil)
                self.doCommand(ctx, "quit", [])
                mpv_terminate_destroy(ctx)
                self.mpv = nil
            }
            self.isInitialized = false
        }
    }

    // MARK: - Private helpers (must be called on mpvQueue)

    private func doLoadFile(_ ctx: OpaquePointer, _ url: String) {
        doCommand(ctx, "loadfile", [url])
    }

    private func doCommand(_ ctx: OpaquePointer, _ name: String, _ args: [String]) {
        var owned: [UnsafeMutablePointer<CChar>?] = [strdup(name)]
        for arg in args { owned.append(strdup(arg)) }
        owned.append(nil)
        var cArgs: [UnsafePointer<CChar>?] = owned.map { $0.map { UnsafePointer($0) } }
        mpv_command(ctx, &cArgs)
        owned.forEach { free($0) }
    }

    private func handleEvents() {
        guard let ctx = mpv else { return }
        while true {
            guard let ev = mpv_wait_event(ctx, 0)?.pointee else { break }
            if ev.event_id == MPV_EVENT_NONE { break }
            switch ev.event_id {
            case MPV_EVENT_FILE_LOADED:     handleFileLoaded()
            case MPV_EVENT_END_FILE:        handleEndFile(ev)
            case MPV_EVENT_PROPERTY_CHANGE: handlePropertyChange(ev)
            case MPV_EVENT_LOG_MESSAGE:
                if let msg = ev.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee,
                   msg.log_level.rawValue <= MPV_LOG_LEVEL_ERROR.rawValue {
                    let text = String(cString: msg.text)
                    DispatchQueue.main.async { [weak self] in self?.onMpvError?(["error": text]) }
                }
            default: break
            }
        }
    }

    private func handleFileLoaded() {
        // Do NOT call mpv_get_property / getTrackInfo() inline here.
        // handleFileLoaded is called from inside handleEvents(), which holds mpv's event lock.
        // Any property read that needs mp_dispatch_lock will deadlock against mpv's own core thread.
        // Defer all reads via mpvQueue.async — serial queue guarantees this runs after
        // handleEvents() fully unwinds, by which point mpv's core lock is free.
        mpvQueue.async { [weak self] in
            guard let self, let ctx = self.mpv else { return }
            var duration: Double = 0
            mpv_get_property(ctx, "duration", MPV_FORMAT_DOUBLE, &duration)
            let tracks = self.getTrackInfo()
            if self.pendingPaused {
                var flag: Int32 = 1
                mpv_set_property(ctx, "pause", MPV_FORMAT_FLAG, &flag)
            }
            if self.pendingSeek >= 0 {
                self.doCommand(ctx, "seek", [self.pendingSeek.description, "absolute"])
                self.pendingSeek = -1
            }
            DispatchQueue.main.async { [weak self] in
                self?.onMpvLoad?(["duration": duration, "audioTracks": tracks.audio, "textTracks": tracks.text])
            }
        }
    }

    private func handleEndFile(_ ev: mpv_event) {
        if let ef = ev.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee, ef.error < 0 {
            let code = ef.error
            DispatchQueue.main.async { [weak self] in
                self?.onMpvError?(["error": "Playback error (code: \(code))"])
            }
        } else {
            DispatchQueue.main.async { [weak self] in self?.onMpvEnd?([:]) }
        }
    }

    private func handlePropertyChange(_ ev: mpv_event) {
        guard let prop = ev.data?.assumingMemoryBound(to: mpv_event_property.self).pointee else { return }
        let name = String(cString: prop.name)
        switch name {
        case "paused-for-cache":
            guard prop.format == MPV_FORMAT_FLAG, let data = prop.data else { break }
            let buffering = data.assumingMemoryBound(to: Int32.self).pointee != 0
            DispatchQueue.main.async { [weak self] in self?.onMpvBuffer?(["isBuffering": buffering]) }
        case "eof-reached":
            guard prop.format == MPV_FORMAT_FLAG,
                  let data = prop.data,
                  data.assumingMemoryBound(to: Int32.self).pointee != 0 else { break }
            DispatchQueue.main.async { [weak self] in self?.onMpvEnd?([:]) }
        case "track-list/count":
            // Defer getTrackInfo() — calling mpv_get_property_string inline while the event
            // loop holds mpv's core lock causes a deadlock on mp_dispatch_lock.
            // mpvQueue is serial so this runs after the current handleEvents call returns.
            mpvQueue.async { [weak self] in
                guard let self, self.mpv != nil else { return }
                let info = self.getTrackInfo()
                DispatchQueue.main.async { [weak self] in
                    self?.onMpvTracksChanged?(["audioTracks": info.audio, "textTracks": info.text])
                }
            }
        default: break
        }
    }

    private func emitProgress() {
        guard let ctx = mpv, isInitialized else { return }
        var timePos: Double = 0
        var dur: Double = 0
        mpv_get_property(ctx, "time-pos", MPV_FORMAT_DOUBLE, &timePos)
        mpv_get_property(ctx, "duration", MPV_FORMAT_DOUBLE, &dur)
        guard timePos > 0 || dur > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onMpvProgress?(["currentTime": timePos, "duration": dur])
        }
    }

    private func getTrackInfo() -> (audio: [[String: Any]], text: [[String: Any]]) {
        guard let ctx = mpv else { return ([], []) }
        var count: Int64 = 0
        mpv_get_property(ctx, "track-list/count", MPV_FORMAT_INT64, &count)
        var audio: [[String: Any]] = []
        var text:  [[String: Any]] = []
        for i in 0..<Int(count) {
            guard let type = getPropertyString(ctx, "track-list/\(i)/type") else { continue }
            var id: Int64 = 0
            mpv_get_property(ctx, "track-list/\(i)/id", MPV_FORMAT_INT64, &id)
            let title = getPropertyString(ctx, "track-list/\(i)/title") ?? ""
            let lang  = getPropertyString(ctx, "track-list/\(i)/lang")  ?? ""
            let name  = title.isEmpty ? (lang.isEmpty ? "Track \(id)" : lang) : title
            let track: [String: Any] = ["id": Int(id), "name": name, "language": lang]
            if type == "audio" { audio.append(track) } else if type == "sub" { text.append(track) }
        }
        return (audio, text)
    }

    private func getPropertyString(_ ctx: OpaquePointer, _ name: String) -> String? {
        guard let cStr = mpv_get_property_string(ctx, name) else { return nil }
        defer { mpv_free(cStr) }
        return String(cString: cStr)
    }
}

// MARK: - MPVMetalView
//
// SW render API: mpv writes decoded frames as BGRA pixels into a CPU buffer.
// We upload to a cached MTLTexture and blit to CAMetalLayer on a dedicated
// renderQueue — the main thread only does a fast flag-check per display tick.

private class MPVMetalView: UIView {

    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?

    // Accessed only on renderQueue
    private var renderTexture: MTLTexture?
    private var renderTextureSize = CGSize.zero
    private var pixelData: [UInt8] = []

    private(set) var renderCtx: OpaquePointer?
    private var displayLink: CADisplayLink?

    // SW decode + Metal encode happen here, never on the main thread
    private let renderQueue = DispatchQueue(label: "mpv.render", qos: .userInteractive)
    // Guard against concurrent renders; accessed only from main thread
    private var renderInFlight = false

    // MARK: - Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupMetal()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
    }

    func cleanup() {
        displayLink?.invalidate()
        displayLink = nil
        // Wait for any in-flight render to finish before freeing the context
        renderQueue.sync {}
        if let ctx = renderCtx {
            mpv_render_context_set_update_callback(ctx, nil, nil)
            mpv_render_context_free(ctx)
            renderCtx = nil
        }
    }

    deinit { cleanup() }

    // MARK: - Metal setup

    private func setupMetal() {
        guard let dev = MTLCreateSystemDefaultDevice() else { return }
        device = dev
        commandQueue = dev.makeCommandQueue()

        metalLayer.device = dev
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.contentsScale = UIScreen.main.scale

        buildPipeline(device: dev)

        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func buildPipeline(device: MTLDevice) {
        let src = """
        #include <metal_stdlib>
        using namespace metal;

        struct Vout { float4 pos [[position]]; float2 uv; };

        vertex Vout vtx(uint id [[vertex_id]]) {
            constexpr float2 p[4] = {{-1, 1}, {1, 1}, {-1, -1}, {1, -1}};
            constexpr float2 t[4] = {{ 0, 0}, {1, 0}, { 0,  1}, {1,  1}};
            return { float4(p[id], 0, 1), t[id] };
        }

        fragment float4 frg(Vout in [[stage_in]],
                            texture2d<float> tex [[texture(0)]],
                            sampler s           [[sampler(0)]]) {
            return tex.sample(s, in.uv);
        }
        """
        guard
            let lib   = try? device.makeLibrary(source: src, options: nil),
            let vtxFn = lib.makeFunction(name: "vtx"),
            let frgFn = lib.makeFunction(name: "frg")
        else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vtxFn
        desc.fragmentFunction = frgFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineState = try? device.makeRenderPipelineState(descriptor: desc)

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        samplerState = device.makeSamplerState(descriptor: sd)
    }

    // MARK: - mpv render context (called on mpvQueue)

    func initMpvRender(_ mpvCtx: OpaquePointer) {
        "sw".withCString { swPtr in
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE,
                                 data: UnsafeMutableRawPointer(mutating: swPtr)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            var ctx: OpaquePointer?
            if mpv_render_context_create(&ctx, mpvCtx, &params) == 0, let ctx {
                renderCtx = ctx
            }
        }
    }

    // MARK: - Render loop

    // Runs on main thread via CADisplayLink.
    // Only checks the update flag here; all heavy work is dispatched to renderQueue.
    @objc private func tick() {
        // Check renderInFlight BEFORE consuming the flag — if we can't render yet, preserve it
        guard !renderInFlight, let ctx = renderCtx else { return }
        guard mpv_render_context_update(ctx) & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 else { return }

        // Capture layout values on main (UIKit) before handing off to renderQueue
        let scale = metalLayer.contentsScale
        let w = Int(bounds.width  * scale)
        let h = Int(bounds.height * scale)
        guard w > 0, h > 0 else { return }

        let targetSize = CGSize(width: w, height: h)
        if metalLayer.drawableSize != targetSize {
            metalLayer.drawableSize = targetSize
        }

        renderInFlight = true
        renderQueue.async { [weak self] in
            self?.renderFrame(ctx: ctx, w: w, h: h)
            DispatchQueue.main.async { self?.renderInFlight = false }
        }
    }

    // Runs entirely on renderQueue — never blocks the main thread.
    private func renderFrame(ctx: OpaquePointer, w: Int, h: Int) {
        guard let pipeline = pipelineState, let sampler = samplerState else { return }

        let needed = w * h * 4
        if pixelData.count < needed {
            pixelData = [UInt8](repeating: 0, count: needed)
        }

        // Ask mpv to SW-render the current frame into our pixel buffer
        pixelData.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            var size: [Int32] = [Int32(w), Int32(h)]
            var stride: Int   = w * 4
            "bgra".withCString { fmtCStr in
                var fmtPtr: UnsafePointer<Int8> = fmtCStr
                withUnsafeMutablePointer(to: &fmtPtr) { fmtPtrPtr in
                    size.withUnsafeMutableBufferPointer { sizeBuf in
                        withUnsafeMutablePointer(to: &stride) { strideBuf in
                            var rp: [mpv_render_param] = [
                                mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE,    data: sizeBuf.baseAddress),
                                mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT,  data: fmtPtrPtr),
                                mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE,  data: strideBuf),
                                mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: base),
                                mpv_render_param(type: MPV_RENDER_PARAM_INVALID,    data: nil),
                            ]
                            mpv_render_context_render(ctx, &rp)
                        }
                    }
                }
            }
        }

        // Upload to a cached MTLTexture (reallocate only on size change)
        let targetSize = CGSize(width: w, height: h)
        if renderTexture == nil || renderTextureSize != targetSize {
            let td = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            td.usage = .shaderRead
            renderTexture     = device.makeTexture(descriptor: td)
            renderTextureSize = targetSize
        }
        guard let texture = renderTexture else { return }

        pixelData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(
                region:      MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                       size:   MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0,
                withBytes:   base,
                bytesPerRow: w * 4)
        }

        // Blit texture to CAMetalLayer drawable (Metal is thread-safe)
        guard
            let drawable = metalLayer.nextDrawable(),
            let cmdBuf   = commandQueue.makeCommandBuffer()
        else { return }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture     = drawable.texture
        rpd.colorAttachments[0].loadAction  = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }
}
