import Foundation
import ScriptingBridge

// --- PROTOCOLOS DE SCRIPTING BRIDGE PARA COMUNICARSE CON REPRODUCTORES DE MACOS (FALLBACK) ---

@objc public protocol SBApplicationProtocol {
    func isRunning() -> Bool
}

@objc public protocol MusicTrackProtocol {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var duration: Double { get }
}

@objc public protocol MusicApplicationProtocol: SBApplicationProtocol {
    @objc optional var currentTrack: MusicTrackProtocol { get }
    @objc optional var playerState: Int { get }
    @objc optional var playerPosition: Double { get }
}

@objc public protocol SpotifyTrackProtocol {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var duration: Int { get }
}

@objc public protocol SpotifyApplicationProtocol: SBApplicationProtocol {
    @objc optional var currentTrack: SpotifyTrackProtocol { get }
    @objc optional var playerState: Int { get }
    @objc optional var playerPosition: Double { get }
}

public struct TrackState {
    public let title: String
    public let artist: String
    public let album: String
    public let isPlaying: Bool
    public let positionMs: Int64
    public let durationMs: Int64
}

// --- LECTOR DE MEDIAREMOTE PRIVADO (UNIVERSAL) ---
#if os(macOS)
import Darwin

typealias MRMediaRemoteGetNowPlayingInfoType = @convention(c) (DispatchQueue, @escaping (NSDictionary) -> Void) -> Void

class MediaRemoteReader {
    private var getNowPlayingInfoFunc: MRMediaRemoteGetNowPlayingInfoType?
    
    init() {
        // Cargar dinámicamente el framework privado para evitar problemas de enlazado y permitir compilar en cualquier máquina
        if let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) {
            if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
                self.getNowPlayingInfoFunc = unsafeBitCast(sym, to: MRMediaRemoteGetNowPlayingInfoType.self)
            }
        }
    }
    
    func getNowPlayingState() async -> TrackState? {
        guard let getNowPlayingInfo = getNowPlayingInfoFunc else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            getNowPlayingInfo(DispatchQueue.global(qos: .userInitiated)) { info in
                let dict = info as? [String: Any] ?? [:]
                
                guard let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
                      let artist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let album = dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
                let durationSec = dict["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0.0
                let elapsedSec = dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0.0
                let rate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0.0
                
                let isPlaying = rate > 0.0
                
                // Extraer identificador del reproductor
                var clientBundleId = ""
                if let clientProps = dict["kMRMediaRemoteNowPlayingInfoClientProperties"] as? [String: Any] {
                    clientBundleId = clientProps["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String ?? ""
                }
                
                // Filtrar navegadores web para evitar spam de videos/pestañas
                let ignoredKeywords = ["chrome", "safari", "firefox", "edge", "brave", "opera", "vivaldi", "zen"]
                let clientLower = clientBundleId.lowercased()
                let isIgnored = ignoredKeywords.contains { clientLower.contains($0) }
                
                if isIgnored {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: TrackState(
                    title: title,
                    artist: artist,
                    album: album,
                    isPlaying: isPlaying,
                    positionMs: Int64(elapsedSec * 1000.0),
                    durationMs: Int64(durationSec * 1000.0)
                ))
            }
        }
    }
}
#endif

// --- IMPLEMENTACIÓN PRINCIPAL DE MUSICREADER ---

public class MusicReader {
    private let musicBundleId = "com.apple.Music"
    private let spotifyBundleId = "com.spotify.client"
    private let mediaRemote = MediaRemoteReader()
    
    public init() {}
    
    public func getCurrentTrack() async -> TrackState? {
        // 1. Intentar con MediaRemote (Soporta universalmente VLC, IINA, etc.)
        if let state = await mediaRemote.getNowPlayingState() {
            return state
        }
        
        // 2. Fallback usando Scripting Bridge si macOS 15.4+ bloqueó el acceso directo a MediaRemote
        return getScriptingBridgeTrack()
    }
    
    private func getScriptingBridgeTrack() -> TrackState? {
        // Fallback a Apple Music
        if let app = SBApplication(bundleIdentifier: musicBundleId) as? MusicApplicationProtocol, app.isRunning() {
            let stateVal = app.playerState ?? 0
            let isPlaying = stateVal == 1800426323 // 'kPSP' (reproduciendo)
            
            if let track = app.currentTrack {
                let title = track.name ?? "Unknown Track"
                let artist = track.artist ?? "Unknown Artist"
                let album = track.album ?? "Unknown Album"
                let durationSec = track.duration ?? 0.0
                let positionSec = app.playerPosition ?? 0.0
                
                return TrackState(
                    title: title,
                    artist: artist,
                    album: album,
                    isPlaying: isPlaying,
                    positionMs: Int64(positionSec * 1000.0),
                    durationMs: Int64(durationSec * 1000.0)
                )
            }
        }
        
        // Fallback a Spotify
        if let app = SBApplication(bundleIdentifier: spotifyBundleId) as? SpotifyApplicationProtocol, app.isRunning() {
            let stateVal = app.playerState ?? 0
            let isPlaying = stateVal == 1800426323 // 'kPSP' (reproduciendo)
            
            if let track = app.currentTrack {
                let title = track.name ?? "Unknown Track"
                let artist = track.artist ?? "Unknown Artist"
                let album = track.album ?? "Unknown Album"
                let durationMs = Int64(track.duration ?? 0)
                let positionSec = app.playerPosition ?? 0.0
                
                return TrackState(
                    title: title,
                    artist: artist,
                    album: album,
                    isPlaying: isPlaying,
                    positionMs: Int64(positionSec * 1000.0),
                    durationMs: durationMs
                )
            }
        }
        
        return nil
    }
}
