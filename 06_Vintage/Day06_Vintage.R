# #30DayMapChallenge 2026 
# Day 6 – Vintage
# Berlin Blueprint
# K. Wiese

# LIBRERÍAS
library(sf)
library(dplyr)
library(ggplot2)
library(ggspatial)
library(scales)
library(rnaturalearth)
library(rnaturalearthdata)
library(here)

sf_use_s2(FALSE)
set.seed(1842)

crs_berlin <- 25833     # ETRS89 / UTM 33N

# ------------------------------------------------------------
# Estilo: "cianotipo" = líneas blancas sobre papel azul (blueprint clásico)
#         "diazo"     = líneas azules sobre papel claro (copia heliográfica)
# ------------------------------------------------------------
estilo <- "diazo"

# Letra técnica: DIN
# Alternativas: "ISOCPEUR"
if (.Platform$OS.type == "windows") {
  windowsFonts(Bahnschrift = windowsFont("Bahnschrift"))
  fuente <- "Bahnschrift"
} else {
  fuente <- "sans"
}

pal <- switch(estilo,
  cianotipo = list(fondo = c("#123468", "#1F4D8F", "#3769AE"), linea = "#F2F6FF",
                   acento = "#BFD7FF", sombra = "#0F2D5C"),
  diazo     = list(fondo = c("#F1EEE2", "#E8E4D3", "#DCD6BF"), linea = "#2C3E8C",
                   acento = "#5A6DB5", sombra = "#B9B29A")
)
L  <- pal$linea
L2 <- pal$acento
Fondo <- pal$fondo[2]

# Textos totales
# ------------------------------------------------------------
txt <- list(
    sufijo  = "_EN",
    dec     = ".",
    titulo  = "BERLIN",
    subtit  = "CITY PLAN · STREETS, WATER, GREEN SPACE",
    campos  = c(massstab = "SCALE", proj = "PROJECTION", daten = "DATA",
                gez = "DRAWN BY", datum = "DATE", blatt = "SHEET"),
    escala  = "1 : %s (at %s × %s cm)",
    proj    = "ETRS89 / UTM 33N · EPSG:25833",
    daten   = "© OpenStreetMap contributors, Geofabrik %s",
    datum   = "2026-11-06",
    blatt   = "6 / 30",
    reto    = "#30DayMapChallenge 2026\nDay 6 · Vintage",
    cota    = "%s km"
  )

dia <- here("06_Vintage")

# 1. LÍMITE DE BERLÍN Y BEZIRKE (caché del día 1)
dir_dia1 <- here("01_Points", "data")
berlin  <- st_read(file.path(dir_dia1, "berlin_limite.gpkg"), quiet = TRUE) %>%
  st_transform(crs_berlin) %>%
  st_union() %>%
  st_sf(geometry = .)
bezirke <- st_read(file.path(dir_dia1, "osm_bezirke.gpkg"), quiet = TRUE) %>%
  st_transform(crs_berlin) %>%
  st_filter(st_buffer(berlin, -500)) %>%
  filter(!is.na(name))

# Hoja: área de dibujo + franja del marco con zonas (A–F, 1–8)
# ------------------------------------------------------------
bb <- st_bbox(berlin)
ancho <- unname(bb["xmax"] - bb["xmin"])
alto  <- unname(bb["ymax"] - bb["ymin"])
dx0 <- unname(bb["xmin"]) - 0.07 * ancho
dx1 <- unname(bb["xmax"]) + 0.07 * ancho
dy0 <- unname(bb["ymin"]) - 0.08 * alto
dy1 <- unname(bb["ymax"]) + 0.10 * alto
banda <- 0.022 * (dx1 - dx0)
lim_x <- c(dx0 - banda, dx1 + banda)
lim_y <- c(dy0 - banda, dy1 + banda)
W <- diff(lim_x); H <- diff(lim_y)

ancho_in <- 16                     # tamaño de salida
alto_in  <- ancho_in * H / W

# Escala real del PNG impreso a ese tamaño
escala_n <- round(W / (ancho_in * 0.0254) / 5000) * 5000

# 2. OSM 
# ============================================================
dir_osm <- here("_datos_osm")
dir.create(dir_osm, showWarnings = FALSE)
geofabrik_zip <- file.path(dir_osm, "berlin-latest-free.shp.zip")
if (!file.exists(geofabrik_zip)) {
  options(timeout = 1800)
  download.file("https://download.geofabrik.de/europe/germany/berlin-latest-free.shp.zip",
                geofabrik_zip, mode = "wb")
}

fecha_osm <- format(file.mtime(geofabrik_zip), "%m/%Y")

leer_geofabrik <- function(capa) {
  st_read(file.path("/vsizip", geofabrik_zip, paste0(capa, ".shp")), quiet = TRUE) %>%
    st_transform(crs_berlin) %>%
    st_make_valid()
}

verdes <- leer_geofabrik("gis_osm_landuse_a_free_1") %>%
  filter(fclass %in% c("forest", "park", "cemetery", "allotments", "recreation_ground")) %>%
  mutate(clase = ifelse(fclass == "forest", "wald", "park")) %>%
  select(clase)

wasser <- leer_geofabrik("gis_osm_water_a_free_1") %>%
  filter(fclass %in% c("water", "reservoir", "river", "riverbank", "dock")) %>%
  select(geometry)

bahn <- leer_geofabrik("gis_osm_railways_free_1") %>%
  filter(fclass %in% c("rail", "light_rail"), tunnel != "T") %>%
  select(geometry)

strassen <- leer_geofabrik("gis_osm_roads_free_1") %>%
  filter(fclass %in% c("motorway", "trunk", "primary", "secondary", "tertiary",
                       "residential", "living_street", "unclassified")) %>%
  mutate(rango = case_when(
    fclass == "motorway"                          ~ "autobahn",
    fclass %in% c("trunk", "primary")             ~ "haupt",
    fclass %in% c("secondary", "tertiary")        ~ "mittel",
    TRUE                                          ~ "neben")) %>%
  select(rango, geometry)

# 3. DETALLES DE DIBUJO TÉCNICO
# ============================================================
# 3a. Agua: contorno y líneas paralelas hacia dentro (rayado de orilla)
wasser_u <- wasser %>%
  filter(as.numeric(st_area(geometry)) > 20000) %>%
  st_union() %>%
  st_simplify(dTolerance = 5)
wasserlinien <- lapply(c(25, 60, 110, 180), function(d) {
  g <- st_buffer(wasser_u, -d)
  if (st_is_empty(g)) return(NULL)
  st_sf(d = d, geometry = st_cast(st_boundary(g), "MULTILINESTRING"))
}) %>% bind_rows()

# 3b. Papel de cianotipo: manchas, fibras, viñeta y dos pliegues
textura <- function(nx = 1000, ny = round(1000 * H / W)) {
  suave <- function(m, k) {
    out <- m * 0
    for (dx in -k:k) for (dy in -k:k) {
      out <- out + m[pmin(pmax(seq_len(nrow(m)) + dy, 1), nrow(m)),
                     pmin(pmax(seq_len(ncol(m)) + dx, 1), ncol(m))]
    }
    out / (2 * k + 1)^2
  }
  nubes  <- rescale(suave(suave(matrix(runif(nx * ny), ny, nx), 6), 6))
  grano  <- matrix(runif(nx * ny), ny, nx)
  xx <- matrix(rep(seq(-1, 1, length.out = nx), each = ny), ny)
  yy <- matrix(rep(seq(-1, 1, length.out = ny), nx), ny)
  vineta <- pmin(1, (xx^2 + yy^2) / 2)^2
  # pliegues: hoja doblada en tres (vertical) y en dos (horizontal)
  pliegue <- exp(-((xx + 1/3) / 0.006)^2) + exp(-((xx - 1/3) / 0.006)^2) +
             exp(-(yy / 0.006)^2)
  m <- 0.5 + 0.7 * (nubes - 0.5) + 0.14 * (grano - 0.5) - 0.3 * vineta + 0.35 * pliegue
  m <- pmin(pmax(m, 0), 1)
  rampa <- colorRamp(if (estilo == "cianotipo") pal$fondo else rev(pal$fondo))
  matrix(rgb(rampa(as.vector(m)), maxColorValue = 255), ny, nx)
}
papel <- textura()

# 3c. Retícula de 1 km del papel (muy tenue)
red_x <- seq(ceiling(dx0 / 1000) * 1000, dx1, 1000)
red_y <- seq(ceiling(dy0 / 1000) * 1000, dy1, 1000)

# 3d. Cotas: ancho y alto de Berlín
cota_txt <- function(m) sprintf(txt$cota, format(round(m / 1000, 1), decimal.mark = txt$dec, nsmall = 1))
cy_h <- unname(bb["ymax"]) + 0.045 * alto           # cota horizontal (arriba)
cx_v <- unname(bb["xmax"]) + 0.035 * ancho          # cota vertical (derecha)

# 3e. Rótulos de los Bezirke en mayúsculas espaciadas
espaciar <- function(x) vapply(strsplit(toupper(x), ""), paste, "", collapse = " ")
bez_lab <- bezirke %>%
  mutate(lab = gsub("-", "-\n", name),
         lab = vapply(strsplit(lab, "\n"), function(p) paste(espaciar(p), collapse = "\n"), "")) %>%
  st_point_on_surface()

fuera <- st_difference(
  st_as_sfc(st_bbox(c(xmin = lim_x[1] - 5000, xmax = lim_x[2] + 5000,
                      ymin = lim_y[1] - 5000, ymax = lim_y[2] + 5000),
                    crs = st_crs(crs_berlin))),
  st_geometry(berlin))

# 4. Caja par texto abajo a la izquierda
# ======================================
tb_x <- c(dx0, dx0 + 0.31 * W)
tb_y <- c(dy0, dy0 + 0.165 * H)
tw <- diff(tb_x); th <- diff(tb_y)
fx <- function(f) tb_x[1] + f * tw
fy <- function(f) tb_y[1] + f * th

# filas de la caja del texto 
x_ins <- 0.30                       # ancho de la casilla del mapa de ubicación
filas <- c(0, 0.13, 0.26, 0.39, 0.52, 1)
campo <- tibble(
  y   = fy((head(filas, -1)[1:4] + filas[2:5]) / 2),
  key = txt$campos[c("gez", "daten", "proj", "massstab")],
  val = c(paste0("K. WIESE   ", txt$campos["datum"], " ", txt$datum,
                 "   ", txt$campos["blatt"], " ", txt$blatt),
          sprintf(txt$daten, fecha_osm),
          txt$proj,
          sprintf(txt$escala, format(escala_n, big.mark = " "),
                  round(ancho_in * 2.54), round(alto_in * 2.54)))
)

germany <- ne_countries(scale = "large", returnclass = "sf") %>%
  filter(admin == "Germany") %>%
  st_make_valid() %>%
  st_transform(crs_berlin)
inset_map <- ggplot() +
  geom_sf(data = germany, fill = NA, color = L, linewidth = 0.3) +
  geom_sf(data = berlin,  fill = L,  color = L, linewidth = 0.2) +
  coord_sf(crs = crs_berlin, datum = NA) +
  theme_void() +
  theme(plot.margin = margin(0, 0, 0, 0))

# 5. MAPA
rect_l <- function(x0, x1, y0, y1, lw = 0.4, ...) {
  annotate("rect", xmin = x0, xmax = x1, ymin = y0, ymax = y1,
           fill = NA, color = L, linewidth = lw, ...)
}
flecha <- arrow(length = unit(0.18, "cm"), ends = "both", type = "open", angle = 20)

zx <- seq(dx0, dx1, length.out = 9)     # 8 zonas horizontales
zy <- seq(dy0, dy1, length.out = 7)     # 6 zonas verticales

p <- ggplot() +
  annotation_raster(papel, xmin = lim_x[1], xmax = lim_x[2], ymin = lim_y[1], ymax = lim_y[2]) +

  # Retícula tenue del papel
  annotate("segment", x = red_x, xend = red_x, y = dy0, yend = dy1,
           color = L, linewidth = 0.12, alpha = 0.07) +
  annotate("segment", y = red_y, yend = red_y, x = dx0, xend = dx1,
           color = L, linewidth = 0.12, alpha = 0.07) +

  # Verde: bosque con relleno tenue, parques solo contorno
  geom_sf(data = filter(verdes, clase == "wald"), fill = alpha(L, 0.10), color = alpha(L, 0.35),
          linewidth = 0.12) +
  geom_sf(data = filter(verdes, clase == "park"), fill = alpha(L, 0.05), color = alpha(L, 0.45),
          linewidth = 0.15, linetype = "22") +

  # Agua
  geom_sf(data = wasser, fill = alpha(L, 0.12), color = NA) +
  geom_sf(data = wasserlinien, color = L, linewidth = 0.12, alpha = 0.35) +
  geom_sf(data = wasser_u, fill = NA, color = L, linewidth = 0.3, alpha = 0.9) +

  # Calles: más gruesas según rango; autopista con doble línea
  geom_sf(data = filter(strassen, rango == "neben"),  color = L, linewidth = 0.10, alpha = 0.45) +
  geom_sf(data = filter(strassen, rango == "mittel"), color = L, linewidth = 0.25, alpha = 0.75) +
  geom_sf(data = filter(strassen, rango == "haupt"),  color = L, linewidth = 0.45, alpha = 0.9) +
  geom_sf(data = filter(strassen, rango == "autobahn"), color = L, linewidth = 0.95) +
  geom_sf(data = filter(strassen, rango == "autobahn"), color = Fondo, linewidth = 0.45) +

  # Ferrocarril: línea con traviesas
  geom_sf(data = bahn, color = L, linewidth = 1.0, linetype = "13", alpha = 0.7) +
  geom_sf(data = bahn, color = L, linewidth = 0.3) +

  # Alrededores apagados
  geom_sf(data = fuera, fill = alpha(Fondo, 0.6), color = NA) +

  # Límites
  geom_sf(data = bezirke, fill = NA, color = L, linewidth = 0.35, linetype = "42", alpha = 0.8) +
  geom_sf(data = berlin,  fill = NA, color = L, linewidth = 1.1) +
  geom_sf_text(data = bez_lab, aes(label = lab), family = fuente, size = 3.0,
               color = L, lineheight = 0.9, alpha = 0.9) +

  # --- Cotas ---------------------------------------------------
  annotate("segment", x = bb["xmin"], xend = bb["xmin"], y = bb["ymax"] - 0.25 * alto,
           yend = cy_h + 0.012 * alto, color = L, linewidth = 0.2, linetype = "21", alpha = 0.7) +
  annotate("segment", x = bb["xmax"], xend = bb["xmax"], y = bb["ymax"] - 0.45 * alto,
           yend = cy_h + 0.012 * alto, color = L, linewidth = 0.2, linetype = "21", alpha = 0.7) +
  annotate("segment", x = bb["xmin"], xend = bb["xmax"], y = cy_h, yend = cy_h,
           color = L, linewidth = 0.35, arrow = flecha) +
  annotate("label", x = mean(bb[c("xmin", "xmax")]), y = cy_h, label = cota_txt(ancho),
           family = fuente, size = 4.2, color = L, fill = Fondo,
           label.size = 0, label.padding = unit(0.15, "lines")) +
  annotate("segment", y = bb["ymin"], yend = bb["ymin"], x = bb["xmin"] + 0.80 * ancho,
           xend = cx_v + 0.01 * ancho, color = L, linewidth = 0.2, linetype = "21", alpha = 0.7) +
  annotate("segment", y = bb["ymax"], yend = bb["ymax"], x = bb["xmin"] + 0.62 * ancho,
           xend = cx_v + 0.01 * ancho, color = L, linewidth = 0.2, linetype = "21", alpha = 0.7) +
  annotate("segment", y = bb["ymin"], yend = bb["ymax"], x = cx_v, xend = cx_v,
           color = L, linewidth = 0.35, arrow = flecha) +
  annotate("label", x = cx_v, y = mean(bb[c("ymin", "ymax")]), label = cota_txt(alto),
           angle = -90, family = fuente, size = 4.2, color = L, fill = Fondo,
           label.size = 0, label.padding = unit(0.15, "lines")) +

  # --- Marco de la lámina con zonas ----------------------------
  rect_l(lim_x[1] + 0.25 * banda, lim_x[2] - 0.25 * banda,
         lim_y[1] + 0.25 * banda, lim_y[2] - 0.25 * banda, lw = 0.4) +
  rect_l(dx0, dx1, dy0, dy1, lw = 1.1) +
  annotate("segment", x = zx[2:8], xend = zx[2:8], y = dy1, yend = dy1 + 0.75 * banda,
           color = L, linewidth = 0.4) +
  annotate("segment", x = zx[2:8], xend = zx[2:8], y = dy0, yend = dy0 - 0.75 * banda,
           color = L, linewidth = 0.4) +
  annotate("segment", y = zy[2:6], yend = zy[2:6], x = dx0, xend = dx0 - 0.75 * banda,
           color = L, linewidth = 0.4) +
  annotate("segment", y = zy[2:6], yend = zy[2:6], x = dx1, xend = dx1 + 0.75 * banda,
           color = L, linewidth = 0.4) +
  annotate("text", x = rep((zx[-1] + zx[-9]) / 2, 2),
           y = rep(c(dy1 + 0.42 * banda, dy0 - 0.42 * banda), each = 8),
           label = rep(1:8, 2), family = fuente, size = 3.6, color = L) +
  annotate("text", y = rep((zy[-1] + zy[-7]) / 2, 2),
           x = rep(c(dx0 - 0.42 * banda, dx1 + 0.42 * banda), each = 6),
           label = rep(rev(LETTERS[1:6]), 2), family = fuente, size = 3.6, color = L) +

  # --- Schriftfeld (cajetín) -----------------------------------
  annotate("rect", xmin = tb_x[1], xmax = tb_x[2], ymin = tb_y[1], ymax = tb_y[2],
           fill = alpha(Fondo, 0.85), color = NA) +
  rect_l(tb_x[1], tb_x[2], tb_y[1], tb_y[2], lw = 1.1) +
  annotate("segment", x = fx(x_ins), xend = tb_x[2], y = fy(filas[2:5]), yend = fy(filas[2:5]),
           color = L, linewidth = 0.3) +
  annotate("segment", x = fx(x_ins), xend = fx(x_ins), y = tb_y[1], yend = tb_y[2],
           color = L, linewidth = 0.5) +
  annotate("text", x = fx(x_ins + 0.025), y = campo$y + 0.018 * th, label = campo$key,
           hjust = 0, vjust = 0, family = fuente, size = 2.3, color = L2) +
  annotate("text", x = fx(x_ins + 0.025), y = campo$y - 0.006 * th, label = campo$val,
           hjust = 0, vjust = 1, family = fuente, size = 3.0, color = L) +
  annotate("text", x = fx((x_ins + 1) / 2), y = fy(0.83), label = txt$titulo,
           family = fuente, fontface = "bold", size = 17, color = L) +
  annotate("text", x = fx((x_ins + 1) / 2), y = fy(0.645), label = txt$subtit,
           family = fuente, size = 3.0, color = L) +
  annotate("text", x = fx(x_ins / 2), y = fy(0.07), label = txt$reto,
           family = fuente, size = 2.3, color = L2, lineheight = 0.95) +
  annotation_custom(ggplotGrob(inset_map),
                    xmin = fx(0.03), xmax = fx(x_ins - 0.03), ymin = fy(0.17), ymax = fy(0.96)) +

  # --- Norte y escala ------------------------------------------
  annotation_north_arrow(
    location = "tl", height = unit(2.2, "cm"), width = unit(1.4, "cm"),
    pad_x = unit(1.6, "cm"), pad_y = unit(1.4, "cm"),
    style = north_arrow_orienteering(fill = c(L, Fondo), line_col = L,
                                     text_col = L, text_family = fuente, text_size = 11)
  ) +
  annotation_scale(
    location = "br", width_hint = 0.2, pad_x = unit(1.6, "cm"), pad_y = unit(1.5, "cm"),
    style = "ticks", line_col = L, text_col = L, line_width = 1.2,
    text_family = fuente, text_cex = 1.0
  ) +

  coord_sf(crs = crs_berlin, datum = NA, xlim = lim_x, ylim = lim_y, expand = FALSE) +
  theme_void(base_family = fuente) +
  theme(plot.background = element_rect(fill = Fondo, color = NA),
        plot.margin = margin(0, 0, 0, 0))

ggsave(
  filename = file.path(dia, paste0("Day06_Vintage_blueprint", 
                                   txt$sufijo,
                                   if (estilo == "diazo") "_diazo" else "", ".png")),
  plot = p, 
  width = ancho_in, 
  height = alto_in, 
  dpi = 300, 
  bg = Fondo
)
