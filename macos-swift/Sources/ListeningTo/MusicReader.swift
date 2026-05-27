import Foundation
import ScriptingBridge

// --- PROTOCOLOS DE SCRIPTING BRIDGE PARA COMUNICARSE CON REPRODUCTORES DE MACOS ---

@objc public protocol SBApplicationProtocol {
    func isRunning() -> Bool
}

// Protocolos para Apple Music
@objc public protocol MusicTrackProtocol {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var duration: Double { get }
}

@objc public protocol MusicApplicationProtocol: SBApplicationProtocol {
    @objc optional var currentTrack: MusicTrackProtocol { get }
    @objc optional var playerState: Int { get }       // kPlayerStatePlaying = 1800426323 ('kPSP')
    @objc optional var playerPosition: Double { get }  // en segundos
}

// Protocolos para Spotify
@objc public protocol SpotifyTrackProtocol {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var duration: Int { get }          // en milisegundos
}

@objc public protocol SpotifyApplicationProtocol: SBApplicationProtocol {
    @objc optional var currentTrack: SpotifyTrackProtocol { get }
    @objc optional var playerState: Int { get }       // kPlayerStatePlaying = 1800426323 ('kPSP')
    @objc optional var playerPosition: Double { get }  // en segundos
}

public struct TrackState {
    public let title: String
    public let artist: String
    public let album: String
    public let isPlaying: Bool
    public let positionMs: Int64
    public let durationMs: Int64
}

public class MusicReader {
    private let musicBundleId = "com.apple.Music"
    private let spotifyBundleId = "com.spotify.client"
    
    public init() {}
    
    public func getCurrentTrack() -> TrackState? {
        // 1. Intentar con Apple Music
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
        
        // 2. Si Apple Music no está activo, intentar con Spotify
        if let app = SBApplication(bundleIdentifier: spotifyBundleId) as? SpotifyApplicationProtocol, app.isRunning() {
            let stateVal = app.playerState ?? 0
            let isPlaying = stateVal == 1800426323 // 'kPSP' (reproduciendo)
            
            if let track = app.currentTrack {
                let title = track.name ?? "Unknown Track"
                let artist = track.artist ?? "Unknown Artist"
                let album = track.album ?? "Unknown Album"
                
                // Spotify reporta duration en milisegundos (Int)
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
