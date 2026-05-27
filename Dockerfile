FROM rust:1.85-slim-bookworm AS builder

# Instalar dependencias necesarias para compilar GTK, D-Bus y Ayatana AppIndicator
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    libssl-dev \
    libdbus-1-dev \
    libayatana-appindicator3-dev \
    librsvg2-dev \
    libsoup-3.0-dev \
    libwebkit2gtk-4.1-dev \
    file \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copiar archivos de configuración para cachear dependencias
COPY src-tauri/Cargo.toml src-tauri/Cargo.lock ./src-tauri/

# Crear archivos ficticios para que Cargo compile las dependencias primero
RUN mkdir -p src-tauri/src && \
    echo "fn main() {}" > src-tauri/src/main.rs && \
    echo "pub fn run() {}" > src-tauri/src/lib.rs && \
    echo "fn main() {}" > src-tauri/build.rs

# Cachear la compilación de dependencias de Rust
RUN cargo build --release --manifest-path src-tauri/Cargo.toml

# Ahora copiar el código real de la aplicación y la carpeta frontend Dist (src)
COPY src ./src
COPY src-tauri/build.rs ./src-tauri/build.rs
COPY src-tauri/tauri.conf.json ./src-tauri/tauri.conf.json
COPY src-tauri/capabilities ./src-tauri/capabilities
COPY src-tauri/icons ./src-tauri/icons
COPY src-tauri/src ./src-tauri/src

# Eliminar / refrescar marcas de tiempo para forzar la compilación real del código
RUN touch src-tauri/src/main.rs src-tauri/src/lib.rs src-tauri/build.rs

# Compilar el ejecutable final para Linux
RUN cargo build --release --manifest-path src-tauri/Cargo.toml

# Configurar el punto de entrada para exportar el ejecutable compilado
VOLUME /out
CMD ["sh", "-c", "cp /app/src-tauri/target/release/ListeningTo /out/ListeningTo && echo '¡Compilación exitosa! El binario de Linux ha sido copiado a la carpeta de salida montada.'"]
