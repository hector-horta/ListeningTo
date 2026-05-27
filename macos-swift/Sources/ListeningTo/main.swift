import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var timer: Timer?
    let musicReader = MusicReader()
    let discordRpc = DiscordIPC(clientId: "1508881392820420878")
    
    var lastTitle = ""
    var lastArtist = ""
    var lastIsPlaying = false
    var lastSentTime = Date()
    var lastPositionMs: Int64 = 0
    var isCurrentlyActive = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cambiar la política de activación a .accessory
        // Esto oculta el icono de la aplicación en el Dock y evita crear ventanas principales,
        // haciendo que viva únicamente en la barra de menú superior.
        NSApp.setActivationPolicy(.accessory)
        
        // Configurar el item en la barra de menú (status bar)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Usar icono de nota musical del sistema
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "ListeningTo")
            } else {
                // Fallback para versiones antiguas
                button.title = "🎵"
            }
        }
        
        // Configurar el menú contextual al hacer clic en el icono del menú bar
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Exit ListeningTo",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem?.menu = menu
        
        print("[App] ListeningTo macOS (Swift) iniciado exitosamente.")
        print("[App] Monitoreando Apple Music y Spotify...")
        
        // Iniciar temporizador recurrente cada 5 segundos
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollMediaState()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Desconectar y limpiar presencia al salir
        discordRpc.disconnect()
    }
    
    func pollMediaState() {
        guard let state = musicReader.getCurrentTrack() else {
            if isCurrentlyActive {
                print("[App] Nada activo en macOS. Limpiando presencia...")
                discordRpc.clearActivity()
                isCurrentlyActive = false
                
                lastTitle = ""
                lastArtist = ""
                lastIsPlaying = false
                lastPositionMs = 0
            }
            return
        }
        
        let title = state.title
        let artist = state.artist
        let album = state.album
        let isPlaying = state.isPlaying
        let positionMs = state.positionMs
        let durationMs = state.durationMs
        
        let songChanged = title != lastTitle || artist != lastArtist
        let playStatusChanged = isPlaying != lastIsPlaying
        
        // Si no está reproduciendo, limpiar presencia
        if !isPlaying {
            if isCurrentlyActive {
                print("[App] Música pausada en macOS. Limpiando presencia...")
                discordRpc.clearActivity()
                isCurrentlyActive = false
                
                lastTitle = ""
                lastArtist = ""
                lastIsPlaying = false
                lastPositionMs = 0
            }
            return
        }
        
        // Detectar si el usuario adelantó o retrocedió la canción (seek)
        var userSeeked = false
        if isPlaying && lastIsPlaying && !songChanged {
            let elapsedMs = Int64(Date().timeIntervalSince(lastSentTime) * 1000.0)
            let expectedPosition = lastPositionMs + elapsedMs
            if abs(positionMs - expectedPosition) > 3000 {
                userSeeked = true
                print("[App] Salto de tiempo (seek) detectado: de \(expectedPosition)ms a \(positionMs)ms")
            }
        }
        
        // Actualizar si algo relevante cambió
        if songChanged || playStatusChanged || userSeeked {
            lastTitle = title
            lastArtist = artist
            lastIsPlaying = isPlaying
            lastPositionMs = positionMs
            lastSentTime = Date()
            
            print("[App] Actualizando presencia: \"\(title)\" - \(artist)")
            discordRpc.updateActivity(
                title: title,
                artist: artist,
                album: album,
                isPlaying: isPlaying,
                positionMs: positionMs,
                durationMs: durationMs
            )
            isCurrentlyActive = true
        }
    }
}

// Iniciar ciclo de vida de la aplicación de macOS
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
