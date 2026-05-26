use std::error::Error;
use std::time::{SystemTime, UNIX_EPOCH};
use discord_rich_presence::{activity, DiscordIpc, DiscordIpcClient};

pub struct DiscordRpcManager {
    client_id: String,
    client: Option<DiscordIpcClient>,
}

impl DiscordRpcManager {
    pub fn new(client_id: &str) -> Self {
        Self {
            client_id: client_id.to_string(),
            client: None,
        }
    }

    pub fn connect(&mut self) -> bool {
        if self.client.is_some() {
            return true;
        }

        println!("[Discord] Intentando conectar con Discord...");
        let mut client = DiscordIpcClient::new(&self.client_id);
        match client.connect() {
            Ok(_) => {
                println!("[Discord] Conectado exitosamente y listo.");
                self.client = Some(client);
                true
            }
            Err(e) => {
                eprintln!("[Discord] Error al conectar cliente RPC: {:?}", e);
                false
            }
        }
    }

    pub fn update_activity(
        &mut self,
        title: &str,
        artist: &str,
        album: &str,
        is_playing: bool,
        position_ms: i64,
        duration_ms: i64,
        artwork_url: Option<&str>,
    ) -> Result<(), Box<dyn Error>> {
        if self.client.is_none() {
            self.connect();
        }

        let client = match &mut self.client {
            Some(c) => c,
            None => return Err("Discord client not connected".into()),
        };

        // Determine large image key
        let large_image_key = artwork_url.unwrap_or("apple_music_logo");
        let large_image_text = if album.is_empty() { "Apple Music" } else { album };

        // Determine start and end timestamps (in seconds)
        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64;
        let start_timestamp = (now_ms - position_ms) / 1000;
        let end_timestamp = start_timestamp + (duration_ms / 1000);

        let mut activity = activity::Activity::new();

        // Use a local String variable to extend its lifetime for the borrow checker
        let state_str: String;

        if is_playing {
            state_str = format!("de {}", artist);
            activity = activity
                .details(title)
                .state(&state_str)
                .assets(activity::Assets::new()
                    .large_image(large_image_key)
                    .large_text(large_image_text)
                    .small_image("play_icon")
                    .small_text("Reproduciendo en Apple Music")
                )
                .timestamps(activity::Timestamps::new()
                    .start(start_timestamp)
                    .end(end_timestamp)
                );
        } else {
            return self.clear_activity();
        }

        if let Err(e) = client.set_activity(activity) {
            eprintln!("[Discord] Error al actualizar actividad: {:?}", e);
            self.client = None; // Reset client to force reconnection
            return Err(e.into());
        }

        Ok(())
    }

    pub fn clear_activity(&mut self) -> Result<(), Box<dyn Error>> {
        if let Some(client) = &mut self.client {
            if let Err(e) = client.clear_activity() {
                eprintln!("[Discord] Error al limpiar actividad: {:?}", e);
                self.client = None; // Force reconnection
                return Err(e.into());
            }
        }
        Ok(())
    }

    #[allow(dead_code)]
    pub fn destroy(&mut self) {
        if let Some(mut client) = self.client.take() {
            let _ = client.clear_activity();
            let _ = client.close();
        }
    }
}
