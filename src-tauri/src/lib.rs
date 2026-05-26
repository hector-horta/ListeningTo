mod media_reader;
mod discord_rpc;

async fn get_artwork_url(client: &reqwest::Client, artist: &str, title: &str) -> Option<String> {
    let query = format!("{} {}", artist, title);
    println!("[App] Buscando portada para: \"{}\" - {}", title, artist);
    let url = "https://itunes.apple.com/search";
    
    let res = client.get(url)
        .query(&[
            ("term", query.as_str()),
            ("media", "music"),
            ("entity", "song"),
            ("limit", "1")
        ])
        .send()
        .await
        .ok()?;

    if !res.status().is_success() {
        return None;
    }

    #[derive(serde::Deserialize)]
    struct ITunesResult {
        #[serde(rename = "artworkUrl100")]
        artwork_url_100: Option<String>,
    }

    #[derive(serde::Deserialize)]
    struct ITunesResponse {
        #[serde(rename = "resultCount")]
        result_count: usize,
        results: Vec<ITunesResult>,
    }

    let response_data: ITunesResponse = res.json().await.ok()?;
    if response_data.result_count > 0 && !response_data.results.is_empty() {
        if let Some(url100) = response_data.results[0].artwork_url_100.clone() {
            let high_res_url = url100.replace("/100x100bb.jpg", "/600x600bb.jpg");
            return Some(high_res_url);
        }
    }

    None
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            // Configurar el menú del tray
            let quit_i = tauri::menu::MenuItem::with_id(app, "quit", "Exit ListeningTo", true, None::<&str>)?;
            let menu = tauri::menu::Menu::with_items(app, &[&quit_i])?;
            
            // Cargar el icono del tray
            let tray_icon_bytes = include_bytes!("../icons/32x32.png");
            let tray_image = tauri::image::Image::from_bytes(tray_icon_bytes)?;

            let _tray = tauri::tray::TrayIconBuilder::new()
                .icon(tray_image)
                .menu(&menu)
                .on_menu_event(|app, event| {
                    if event.id.as_ref() == "quit" {
                        app.exit(0);
                    }
                })
                .build(app)?;

            // Iniciar el loop asíncrono de monitoreo en segundo plano
            tauri::async_runtime::spawn(async move {
                let media_reader = media_reader::MediaReader::new();

                let mut discord_rpc = discord_rpc::DiscordRpcManager::new("1508881392820420878");
                let http_client = reqwest::Client::new();

                let mut last_title = String::new();
                let mut last_artist = String::new();
                let mut last_is_playing = false;
                let mut last_artwork_url: Option<String> = None;
                let mut last_sent_position = 0;
                let mut last_sent_time = std::time::Instant::now();
                let mut is_currently_active = false;

                loop {
                    tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;

                    let state = media_reader.get_current_state().await;

                    // Caso 1: Nada activo (música pausada o ausente)
                    if state.is_none() {
                        if is_currently_active {
                            println!("[App] Nada activo. Limpiando presencia...");
                            let _ = discord_rpc.clear_activity();
                            is_currently_active = false;
                            
                            last_title.clear();
                            last_artist.clear();
                            last_is_playing = false;
                            last_artwork_url = None;
                            last_sent_position = 0;
                        }
                        continue;
                    }

                    // Extraer valores de música
                    let state_val = state.as_ref().unwrap();
                    let is_playing = state_val.is_playing;
                    let title = state_val.title.as_str();
                    let artist = state_val.artist.as_str();
                    let album = state_val.album.as_str();
                    let position_ms = state_val.position_ms;
                    let duration_ms = state_val.duration_ms;

                    // Detectar cambios en música
                    let song_changed = title != last_title || artist != last_artist;
                    let play_status_changed = is_playing != last_is_playing;

                    // Si está pausada la música, limpiamos presencia
                    if !is_playing {
                        if is_currently_active {
                            println!("[App] Música pausada. Limpiando presencia...");
                            let _ = discord_rpc.clear_activity();
                            is_currently_active = false;
                            
                            last_title.clear();
                            last_artist.clear();
                            last_is_playing = false;
                            last_artwork_url = None;
                            last_sent_position = 0;
                        }
                        continue;
                    }

                    // Detectar si el usuario adelantó o retrocedió la canción (seek)
                    let mut user_seeked = false;
                    if is_playing && last_is_playing && !song_changed {
                        let elapsed = last_sent_time.elapsed().as_millis() as i64;
                        let expected_position = last_sent_position + elapsed;
                        if (position_ms - expected_position).abs() > 3000 {
                            user_seeked = true;
                            println!("[App] Salto de tiempo (seek) detectado: de {}ms a {}ms", expected_position, position_ms);
                        }
                    }

                    // Actualizar si algo relevante cambió
                    if song_changed || play_status_changed || user_seeked {
                        last_title = title.to_string();
                        last_artist = artist.to_string();
                        last_is_playing = is_playing;
                        last_sent_position = position_ms;
                        last_sent_time = std::time::Instant::now();

                        // Buscar carátula si cambió la canción o no está cargada
                        if song_changed || last_artwork_url.is_none() {
                            last_artwork_url = get_artwork_url(&http_client, artist, title).await;
                        }

                        let _ = discord_rpc.update_activity(
                            title,
                            artist,
                            album,
                            is_playing,
                            position_ms,
                            duration_ms,
                            last_artwork_url.as_deref()
                        );
                        is_currently_active = true;
                    }
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
