import Foundation
import ScriptingBridge

// --- PROTOCOLOS DE SCRIPTING BRIDGE PARA COMUNICARSE CON REPRODUCTORES DE MACOS (FALLBACK) ---

@objc(SBApplicationProtocol)
public protocol SBApplicationProtocol {
    func isRunning() -> Bool
}

@objc(MusicTrackProtocol)
public protocol MusicTrackProtocol {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var duration: Double { get }
}

@objc(MusicApplicationProtocol)
public protocol MusicApplicationProtocol: SBApplicationProtocol {
    @objc optional var currentTrack: MusicTrackProtocol { get }
    @objc optional var playerState: Int { get }
    @objc optional var playerPosition: Double { get }
}

@objc(SpotifyTrackProtocol)
public protocol SpotifyTrackProtocol {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var duration: Int { get }
}

@objc(SpotifyApplicationProtocol)
public protocol SpotifyApplicationProtocol: SBApplicationProtocol {
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
    public let artworkUrl: String?
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
            } else {
                print("[MediaRemote] Error: No se encontró el símbolo MRMediaRemoteGetNowPlayingInfo.")
            }
        } else {
            if let err = dlerror() {
                let errMsg = String(cString: err)
                print("[MediaRemote] Error al cargar framework: \(errMsg)")
            } else {
                print("[MediaRemote] Error desconocido al cargar framework.")
            }
        }
    }
    
    func getNowPlayingState() async -> TrackState? {
        guard let getNowPlayingInfo = getNowPlayingInfoFunc else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            getNowPlayingInfo(DispatchQueue.global(qos: .userInitiated)) { info in
                print("[MediaRemote] Callback invocado.")
                let dict = info as? [String: Any] ?? [:]
                
                guard let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
                      let artist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String else {
                    print("[MediaRemote] Advertencia: Título o artista nulos en el diccionario.")
                    continuation.resume(returning: nil)
                    return
                }
                
                print("[MediaRemote] Detectado: \(title) - \(artist)")
                let album = dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
                let durationSec = dict["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0.0
                let elapsedSec = dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0.0
                let rate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0.0
                
                let isPlaying = rate > 0.0
                print("[MediaRemote] isPlaying (rate > 0): \(isPlaying) (rate: \(rate))")
                
                // Extraer identificador del reproductor
                var clientBundleId = ""
                if let clientProps = dict["kMRMediaRemoteNowPlayingInfoClientProperties"] as? [String: Any] {
                    clientBundleId = clientProps["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String ?? ""
                }
                print("[MediaRemote] Client Bundle ID: \(clientBundleId)")
                
                // Filtrar navegadores web para evitar spam de videos/pestañas
                let ignoredKeywords = ["chrome", "safari", "firefox", "edge", "brave", "opera", "vivaldi", "zen"]
                let clientLower = clientBundleId.lowercased()
                let isIgnored = ignoredKeywords.contains { clientLower.contains($0) }
                
                if isIgnored {
                    print("[MediaRemote] Ignorando reproductor (es navegador): \(clientBundleId)")
                    continuation.resume(returning: nil)
                    return
                }
                
                let artworkUrl = dict["kMRMediaRemoteNowPlayingInfoArtworkIdentifier"] as? String
                print("[MediaRemote] Artwork URL: \(artworkUrl ?? "nil")")
                continuation.resume(returning: TrackState(
                    title: title,
                    artist: artist,
                    album: album,
                    isPlaying: isPlaying,
                    positionMs: Int64(elapsedSec * 1000.0),
                    durationMs: Int64(durationSec * 1000.0),
                    artworkUrl: artworkUrl
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
        print("[ScriptingBridge] Evaluando fallback...")
        
        // 1. Fallback a Apple Music
        if let app = SBApplication(bundleIdentifier: musicBundleId) as AnyObject? {
            let isRunning = app.value(forKey: "isRunning") as? Bool ?? false
            print("[ScriptingBridge] Apple Music ejecutándose: \(isRunning)")
            if isRunning {
                let stateVal = app.value(forKey: "playerState") as? Int ?? 0
                let isPlaying = stateVal == 1800426320 // 'kPSP' (reproduciendo)
                print("[ScriptingBridge] Apple Music playerState: \(stateVal) (isPlaying: \(isPlaying))")
                
                if let track = app.value(forKey: "currentTrack") as AnyObject? {
                    let title = track.value(forKey: "name") as? String ?? "Unknown Track"
                    let artist = track.value(forKey: "artist") as? String ?? "Unknown Artist"
                    let album = track.value(forKey: "album") as? String ?? "Unknown Album"
                    let durationSec = track.value(forKey: "duration") as? Double ?? 0.0
                    let positionSec = app.value(forKey: "playerPosition") as? Double ?? 0.0
                    
                    print("[ScriptingBridge] Apple Music track detectado: \(title) - \(artist)")
                    return TrackState(
                        title: title,
                        artist: artist,
                        album: album,
                        isPlaying: isPlaying,
                        positionMs: Int64(positionSec * 1000.0),
                        durationMs: Int64(durationSec * 1000.0),
                        artworkUrl: nil
                    )
                } else {
                    print("[ScriptingBridge] Track actual de Apple Music es nulo (posible falta de permisos).")
                }
            }
        } else {
            print("[ScriptingBridge] No se pudo instanciar Apple Music SBApplication.")
        }
        
        // 2. Fallback a Spotify
        if let app = SBApplication(bundleIdentifier: spotifyBundleId) as AnyObject? {
            let isRunning = app.value(forKey: "isRunning") as? Bool ?? false
            print("[ScriptingBridge] Spotify ejecutándose: \(isRunning)")
            if isRunning {
                let stateVal = app.value(forKey: "playerState") as? Int ?? 0
                let isPlaying = stateVal == 1800426320 // 'kPSP' (reproduciendo)
                print("[ScriptingBridge] Spotify playerState: \(stateVal) (isPlaying: \(isPlaying))")
                
                if let track = app.value(forKey: "currentTrack") as AnyObject? {
                    let title = track.value(forKey: "name") as? String ?? "Unknown Track"
                    let artist = track.value(forKey: "artist") as? String ?? "Unknown Artist"
                    let album = track.value(forKey: "album") as? String ?? "Unknown Album"
                    
                    let durationMs: Int64
                    if let durDouble = track.value(forKey: "duration") as? Double {
                        durationMs = Int64(durDouble)
                    } else if let durInt = track.value(forKey: "duration") as? Int {
                        durationMs = Int64(durInt)
                    } else {
                        durationMs = 0
                    }
                    let positionSec = app.value(forKey: "playerPosition") as? Double ?? 0.0
                    
                    let artworkUrl = track.value(forKey: "artworkUrl") as? String
                    print("[ScriptingBridge] Spotify artwork URL: \(artworkUrl ?? "nil")")
                    print("[ScriptingBridge] Spotify track detectado: \(title) - \(artist)")
                    return TrackState(
                        title: title,
                        artist: artist,
                        album: album,
                        isPlaying: isPlaying,
                        positionMs: Int64(positionSec * 1000.0),
                        durationMs: durationMs,
                        artworkUrl: artworkUrl
                    )
                } else {
                    print("[ScriptingBridge] Track actual de Spotify es nulo (posible falta de permisos).")
                }
            }
        } else {
            print("[ScriptingBridge] No se pudo instanciar Spotify SBApplication.")
        }
        
        return nil
    }
}
