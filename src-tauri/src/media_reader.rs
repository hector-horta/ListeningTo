#[derive(Debug, Clone)]
pub struct MediaState {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub is_playing: bool,
    pub position_ms: i64,
    pub duration_ms: i64,
}

pub struct MediaReader;

// --- IMPLEMENTACIÓN WINDOWS ---
#[cfg(target_os = "windows")]
use windows::Media::Control::{
    GlobalSystemMediaTransportControlsSession as Session,
    GlobalSystemMediaTransportControlsSessionManager as SessionManager,
    GlobalSystemMediaTransportControlsSessionPlaybackStatus as PlaybackStatus,
};

#[cfg(target_os = "windows")]
impl MediaReader {
    pub fn new() -> Self {
        Self
    }

    pub async fn get_active_session(&self) -> Option<Session> {
        // Re-solicitar el manager en cada ciclo evita problemas de caché de Windows (sesiones estancadas)
        let manager = SessionManager::RequestAsync().ok()?.await.ok()?;
        let sessions = manager.GetSessions().ok()?;
        let ignored_keywords = [
            "chrome", "msedge", "firefox", "brave", "opera", "vivaldi", "zen", "browser", "explorer"
        ];

        for session in sessions {
            if let Ok(app_id) = session.SourceAppUserModelId() {
                let app_id_str = app_id.to_string();
                let app_id_lower = app_id_str.to_lowercase();
                
                // Ignorar navegadores y exploradores de archivos
                let is_ignored = ignored_keywords.iter().any(|&keyword| app_id_lower.contains(keyword));
                println!("[Reader] Sesión encontrada: AppId = '{}', Ignorada = {}", app_id_str, is_ignored);
                if !is_ignored {
                    return Some(session);
                }
            }
        }
        None
    }

    pub async fn get_current_state(&self) -> Option<MediaState> {
        let session = self.get_active_session().await?;
        
        // 1. Estado de reproducción
        let playback_info = session.GetPlaybackInfo().ok()?;
        let status = playback_info.PlaybackStatus().ok()?;
        let is_playing = status == PlaybackStatus::Playing;

        // 2. Propiedades multimedia
        let media_properties = session.TryGetMediaPropertiesAsync().ok()?.await.ok()?;

        let title = media_properties.Title().map(|h| h.to_string()).unwrap_or_else(|_| "Unknown Track".to_string());
        let artist = media_properties.Artist().map(|h| h.to_string()).unwrap_or_else(|_| "Unknown Artist".to_string());
        let album = media_properties.AlbumTitle().map(|h| h.to_string()).unwrap_or_else(|_| "Unknown Album".to_string());

        // 3. Tiempos de la línea de tiempo
        let mut position_ms = 0;
        let mut duration_ms = 0;
        if let Ok(timeline) = session.GetTimelineProperties() {
            if let Ok(pos) = timeline.Position() {
                position_ms = pos.Duration / 10000; // de ticks de 100-ns a ms
            }
            if let Ok(end) = timeline.EndTime() {
                duration_ms = end.Duration / 10000;
            }
        }

        Some(MediaState {
            title,
            artist,
            album,
            is_playing,
            position_ms,
            duration_ms,
        })
    }
}

// --- IMPLEMENTACIÓN LINUX ---
#[cfg(target_os = "linux")]
impl MediaReader {
    pub fn new() -> Self {
        Self
    }

    pub async fn get_current_state(&self) -> Option<MediaState> {
        let player_finder = mpris::PlayerFinder::new().ok()?;
        let players = player_finder.find_all().ok()?;
        
        let ignored_keywords = [
            "chrome", "msedge", "firefox", "brave", "opera", "vivaldi", "zen", "browser", "explorer"
        ];

        for player in players {
            let identity = player.identity();
            let identity_lower = identity.to_lowercase();
            
            // Ignorar navegadores y exploradores de archivos
            let is_ignored = ignored_keywords.iter().any(|&keyword| identity_lower.contains(keyword));
            println!("[Reader] Sesión Linux encontrada: Identity = '{}', Ignorada = {}", identity, is_ignored);
            
            if !is_ignored {
                let playback_status = player.get_playback_status().ok()?;
                let is_playing = playback_status == mpris::PlaybackStatus::Playing;

                let metadata = player.get_metadata().ok()?;
                let title = metadata.title().unwrap_or("Unknown Track").to_string();
                
                let artist = metadata.artists()
                    .map(|a| a.join(", "))
                    .unwrap_or_else(|| "Unknown Artist".to_string());
                
                let album = metadata.album_name().unwrap_or("Unknown Album").to_string();

                let position_ms = player.get_position()
                    .map(|d| d.as_millis() as i64)
                    .unwrap_or(0);
                
                let duration_ms = metadata.length()
                    .map(|d| d.as_millis() as i64)
                    .unwrap_or(0);

                return Some(MediaState {
                    title,
                    artist,
                    album,
                    is_playing,
                    position_ms,
                    duration_ms,
                });
            }
        }
        None
    }
}

// --- SOPORTE CAÍDA (OTRO OS) ---
#[cfg(not(any(target_os = "windows", target_os = "linux")))]
impl MediaReader {
    pub fn new() -> Self {
        Self
    }

    pub async fn get_current_state(&self) -> Option<MediaState> {
        None
    }
}
