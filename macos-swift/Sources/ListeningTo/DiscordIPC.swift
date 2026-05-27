import Foundation

#if os(macOS)
import Darwin

public class DiscordIPC {
    private var socketFd: Int32 = -1
    private let clientId: String
    
    public init(clientId: String) {
        self.clientId = clientId
    }
    
    public func connect() -> Bool {
        if socketFd != -1 { return true }
        
        guard let path = findSocketPath() else {
            print("[Discord] No se encontró ningún socket de Discord corriendo en la máquina.")
            return false
        }
        
        // Crear un socket Unix de tipo flujo (SOCK_STREAM)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            print("[Discord] Error al crear socket descriptor.")
            return false
        }
        
        var addr = sockaddr_un()
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)
        
        let pathBytes = path.utf8CString
        if pathBytes.count > 104 { // Límite estándar de sun_path en BSD
            print("[Discord] La ruta del socket es demasiado larga.")
            Darwin.close(fd)
            return false
        }
        
        // Copiar los bytes de la ruta al miembro sun_path
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            let rawPtr = UnsafeMutableRawPointer(sunPathPtr)
            let typedPtr = rawPtr.bindMemory(to: CChar.self, capacity: 104)
            for i in 0..<pathBytes.count {
                typedPtr[i] = pathBytes[i]
            }
        }
        
        let addrSize = MemoryLayout<sockaddr_un>.size
        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(addrSize))
            }
        }
        
        if connectResult < 0 {
            print("[Discord] No se pudo conectar al socket local. ¿Está Discord abierto?")
            Darwin.close(fd)
            return false
        }
        
        self.socketFd = fd
        print("[Discord] Conectado exitosamente al socket local de Discord en: \(path)")
        
        // Enviar Frame de Handshake (Opcode 0) para registrar el Client ID
        let handshakeJson = "{\"v\":1,\"client_id\":\"\(clientId)\"}"
        sendFrame(opcode: 0, payload: handshakeJson)
        
        // Leer la respuesta inicial para vaciar el socket
        var responseBuffer = [UInt8](repeating: 0, count: 1024)
        _ = Darwin.read(fd, &responseBuffer, responseBuffer.count)
        
        return true
    }
    
    public func updateActivity(
        title: String,
        artist: String,
        album: String,
        isPlaying: Bool,
        positionMs: Int64,
        durationMs: Int64
    ) {
        guard connect() else { return }
        
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let startTimestamp = (nowMs - positionMs) / 1000
        let endTimestamp = startTimestamp + (durationMs / 1000)
        
        let largeImageKey = "apple_music_logo"
        let largeImageText = album.isEmpty ? "Music" : album
        
        let activityJson = """
        {
            "cmd": "SET_ACTIVITY",
            "args": {
                "pid": \(Darwin.getpid()),
                "activity": {
                    "details": "\(escapeJsonString(title))",
                    "state": "de \(escapeJsonString(artist))",
                    "assets": {
                        "large_image": "\(largeImageKey)",
                        "large_text": "\(escapeJsonString(largeImageText))",
                        "small_image": "play_icon",
                        "small_text": "Reproduciendo"
                    },
                    "timestamps": {
                        "start": \(startTimestamp),
                        "end": \(endTimestamp)
                    }
                }
            },
            "nonce": "\(UUID().uuidString)"
        }
        """
        
        // Enviar Frame de Actividad (Opcode 1)
        sendFrame(opcode: 1, payload: activityJson)
    }
    
    public func clearActivity() {
        guard socketFd != -1 else { return }
        
        let activityJson = """
        {
            "cmd": "SET_ACTIVITY",
            "args": {
                "pid": \(Darwin.getpid()),
                "activity": null
            },
            "nonce": "\(UUID().uuidString)"
        }
        """
        sendFrame(opcode: 1, payload: activityJson)
    }
    
    public func disconnect() {
        if socketFd != -1 {
            clearActivity()
            Darwin.close(socketFd)
            socketFd = -1
            print("[Discord] Desconectado del socket.")
        }
    }
    
    private func sendFrame(opcode: Int32, payload: String) {
        guard socketFd != -1 else { return }
        
        let payloadBytes = [UInt8](payload.utf8)
        let payloadLength = UInt32(payloadBytes.count)
        
        // El protocolo IPC de Discord usa una cabecera de 8 bytes:
        // - 4 bytes: Opcode en Little Endian (0 = Handshake, 1 = Frame, 2 = Close)
        // - 4 bytes: Tamaño del Payload en Little Endian
        var header = [UInt8](repeating: 0, count: 8)
        
        header[0] = UInt8(opcode & 0xFF)
        header[1] = UInt8((opcode >> 8) & 0xFF)
        header[2] = UInt8((opcode >> 16) & 0xFF)
        header[3] = UInt8((opcode >> 24) & 0xFF)
        
        header[4] = UInt8(payloadLength & 0xFF)
        header[5] = UInt8((payloadLength >> 8) & 0xFF)
        header[6] = UInt8((payloadLength >> 16) & 0xFF)
        header[7] = UInt8((payloadLength >> 24) & 0xFF)
        
        let frameBytes = header + payloadBytes
        _ = Darwin.write(socketFd, frameBytes, frameBytes.count)
    }
    
    private func findSocketPath() -> String? {
        // En macOS Discord guarda el socket local en carpetas temporales o la carpeta de soporte de Discord
        let tmpKeys = ["TMPDIR", "TEMP", "TMP"]
        var searchDirs = [
            NSTemporaryDirectory(),
            "/tmp",
            "/var/tmp"
        ]
        
        // Agregar directorios de variables de entorno de terminal
        for key in tmpKeys {
            if let val = ProcessInfo.processInfo.environment[key], !val.isEmpty {
                searchDirs.append(val)
            }
        }
        
        let fileManager = FileManager.default
        
        // Intentar encontrar carpetas temporales de sandbox de Discord
        for dir in searchDirs {
            for i in 0..<10 {
                let path = (dir as NSString).appendingPathComponent("discord-ipc-\(i)")
                if fileManager.fileExists(atPath: path) {
                    return path
                }
            }
        }
        
        // Carpeta alternativa en Application Support
        let appSupportDirs = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        if let appSupport = appSupportDirs.first {
            let discordIpcPath = appSupport.appendingPathComponent("discord/ipc-0").path
            if fileManager.fileExists(atPath: discordIpcPath) {
                return discordIpcPath
            }
        }
        
        return nil
    }
    
    private func escapeJsonString(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
#endif
