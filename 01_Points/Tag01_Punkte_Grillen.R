# ============================================================
# #30DayMapChallenge 2026 · Tag 1 – Points
# Grillen in Berlin: offizielle Grillflächen
# K. Wiese
# ============================================================

# ============================================================
# LIBRERÍAS
# ============================================================
library(osmdata)
library(sf)
library(dplyr)
library(ggplot2)
library(stringr)
library(ggspatial)
library(units)
library(ggrepel)
library(rnaturalearth)
library(rnaturalearthdata)
library(here)

Azul  <- "#0047AB"
Texto <- "grey22"
Fuego <- "#E4572E"   # puntos de grill
Brasa <- "#FFB627"   # grill con reserva

crs_berlin <- 25833  # ETRS89 / UTM 33N

# Rutas relativas a la raíz del proyecto (30DayMapChallenge2026.Rproj)
dia      <- here("01_Points")
dir_data <- file.path(dia, "data")
dir.create(dir_data, showWarnings = FALSE)

# ============================================================
# 1. GRILLFLÄCHEN (WFS del Geoportal Berlin)
# ============================================================
# El dataset de daten.berlin.de se publica como WMS (solo imagen),
# pero el mismo servicio ofrece un WFS con las geometrías:
wfs_url <- paste0(
  "https://gdi.berlin.de/services/wfs/grillflaechen?",
  "service=WFS&version=2.0.0&request=GetFeature",
  "&typeNames=grillflaechen:grillflaechen",
  "&outputFormat=application/json&srsName=EPSG:4326"
)
grill_file <- file.path(dir_data, "grillflaechen_berlin.geojson")

if (!file.exists(grill_file)) {
  download.file(wfs_url, grill_file, mode = "wb", quiet = TRUE)
}

grill_poly <- st_read(grill_file, quiet = TRUE) %>%
  st_transform(crs_berlin) %>%
  st_make_valid()

# Convertir polígonos en puntos para una mejor visualización
grill <- grill_poly %>%
  mutate(
    area_m2 = as.numeric(st_area(geometry)),
    label = case_when(
      uid == "02101"  ~ "Volkspark Friedrichshain",
      uid == "02102"  ~ "Görlitzer Park",
      uid == "02103"  ~ "Blücherplatz",
      uid == "040001" ~ "Rudolf-Mosse-Straße",
      uid == "07001"  ~ "Tempelhofer Feld\n(Columbiadamm)",
      uid == "07002"  ~ "Tempelhofer Feld\n(Tempelhofer Damm)",
      TRUE ~ str_trim(adresse)
    ),
    grillarea = factor(grillarea,
                       levels = c("Frei wählbar", "Buchung notwendig"))
  ) %>%
  st_point_on_surface()

n_grill    <- nrow(grill)
area_grill <- sum(grill$area_m2)

# ============================================================
# 2. FUNCIÓN PARA OSM (reintentos + caché)
# ============================================================

# servidores overpass
servidores_overpass <- c(
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter"
)

osm_polys <- function(bbox, features, archivo, intentos = 2) {
  if (file.exists(archivo)) return(st_read(archivo, quiet = TRUE))

  for (i in seq_len(intentos)) {
    for (srv in servidores_overpass) {
      message("Consultando ", basename(archivo), " en ", srv, " ...")
      res <- tryCatch(
        {
          set_overpass_url(srv)         
          opq(bbox, timeout = 300)
        } %>%
          add_osm_features(features = features) %>%
          osmdata_sf(quiet = TRUE),
        error = function(e) { message("  falló: ", conditionMessage(e)); NULL }
      )
      if (!is.null(res)) {
        out <- bind_rows(res$osm_polygons, res$osm_multipolygons)
        out <- out[, intersect(c("name", "admin_level"), names(out))] %>%
          st_zm(drop = TRUE) %>%
          st_make_valid() %>%
          st_transform(crs_berlin)
        st_write(out, archivo, quiet = TRUE, delete_dsn = TRUE)
        return(out)
      }
      Sys.sleep(5)
    }
  }
  stop("No se pudo descargar ", basename(archivo), " desde Overpass.")
}

# ============================================================
# 3. LÍMITE DE BERLÍN Y BEZIRKE (OSM)
# ============================================================
berlin_file <- file.path(dir_data, "berlin_limite.gpkg")

if (file.exists(berlin_file)) {
  berlin <- st_read(berlin_file, quiet = TRUE)
} else {
  q_city <- opq("Berlin, Germany", timeout = 300) %>%
    add_osm_feature("boundary", "administrative") %>%
    add_osm_feature("name", "Berlin")

  city_raw <- osmdata_sf(q_city)

  berlin <- bind_rows(
    city_raw$osm_multipolygons,
    city_raw$osm_polygons
  ) %>%
    st_make_valid() %>%
    filter(name == "Berlin")

  if (nrow(berlin) > 1) {
    berlin <- berlin %>%
      mutate(area = st_area(geometry)) %>%
      slice_max(area, n = 1)
  }

  berlin <- berlin %>%
    select(name, geometry) %>%
    st_transform(crs_berlin)

  st_write(berlin, berlin_file, quiet = TRUE, delete_dsn = TRUE)
}

bbox_berlin <- st_bbox(berlin)
bbox_osm    <- st_bbox(st_transform(berlin, 4326))

bezirke <- osm_polys(
  bbox_osm,
  features = c("\"admin_level\"=\"9\""),
  archivo  = file.path(dir_data, "osm_bezirke.gpkg")
) %>%
  st_filter(st_buffer(berlin, -500))      # solo los 12 Bezirke de Berlín

# ============================================================
# 4. CONTEXTO: AGUA Y ÁREAS VERDES (OSM)
# ============================================================

dir_osm <- here("_datos_osm")
dir.create(dir_osm, showWarnings = FALSE)
geofabrik_zip <- file.path(dir_osm, "berlin-latest-free.shp.zip")

if (!file.exists(geofabrik_zip)) {
  options(timeout = 1800)
  download.file(
    "https://download.geofabrik.de/europe/germany/berlin-latest-free.shp.zip",
    geofabrik_zip, mode = "wb"
  )
}

leer_geofabrik <- function(capa) {
  st_read(file.path("/vsizip", geofabrik_zip, paste0(capa, ".shp")),
          quiet = TRUE) %>%
    st_transform(crs_berlin) %>%
    st_make_valid()
}

water_polys <- leer_geofabrik("gis_osm_water_a_free_1") %>%
  filter(fclass %in% c("water", "reservoir", "river", "riverbank", "dock")) %>%
  select(geometry) %>%
  st_intersection(st_geometry(berlin))

green_polys <- leer_geofabrik("gis_osm_landuse_a_free_1") %>%
  filter(fclass %in% c("park", "forest")) %>%
  select(geometry) %>%
  st_intersection(st_geometry(berlin))

# ============================================================
# 5. MAPA DE UBICACIÓN (INSET MAP)
# ============================================================
germany <- ne_countries(scale = "large", returnclass = "sf") %>%
  filter(admin == "Germany") %>%
  st_make_valid() %>%
  st_transform(crs_berlin)

# Etiqueta "Berlin"
bc    <- st_coordinates(st_centroid(st_geometry(berlin)))
bb_de <- st_bbox(germany)
W_de  <- bb_de["xmax"] - bb_de["xmin"]
H_de  <- bb_de["ymax"] - bb_de["ymin"]

lab_x <- bc[1] - 0.20 * W_de
lab_y <- bc[2] + 0.12 * H_de

inset_map <- ggplot() +
  geom_sf(data = germany, fill = "gray90", color = "black", linewidth = 0.3) +
  geom_sf(data = berlin,  fill = "red",     color = "black", linewidth = 0.2) +
  annotate(
    "curve",
    x = lab_x - 0.01 * W_de, y = lab_y,                        
    xend = bc[1] - 0.03 * W_de, yend = bc[2] + 0.02 * H_de,    
    curvature = -0.4,
    arrow = arrow(length = unit(0.12, "cm"), type = "closed"),
    color = "black",
    linewidth = 0.4
  ) +
  annotate(
    "label",
    x = lab_x, y = lab_y,
    label = "Berlin",
    hjust = 1,
    size = 4,
    fontface = "bold",
    color = "black",
    fill = "white",
    label.size = 0.2,
    label.r = unit(0.15, "lines")
  ) +
  coord_sf(crs = crs_berlin, clip = "off") +
  theme_void()

# Posición del inset
ancho  <- bbox_berlin["xmax"] - bbox_berlin["xmin"]
alto   <- bbox_berlin["ymax"] - bbox_berlin["ymin"]

# ============================================================
# 6. Mapa Grillen Berlin
# ============================================================
p <- ggplot() +
  geom_sf(data = berlin,
          fill = "gray95",
          color = "gray40",
          linewidth = 0.8) +

  geom_sf(data = green_polys,
          fill = "#B7D7A8",
          color = NA,
          alpha = 0.6) +

  geom_sf(data = water_polys,
          fill = "#1f78b4",
          color = NA,
          alpha = 0.85) +

  geom_sf(data = bezirke,
          fill = NA,
          color = "gray55",
          linewidth = 0.3,
          linetype = "dashed") +

  # Halo + punto
  geom_sf(data = grill,
          color = Fuego,
          size = 11,
          alpha = 0.25) +

  geom_sf(data = grill,
          aes(fill = grillarea),
          shape = 21,
          color = "white",
          stroke = 1.2,
          size = 5.5) +

  scale_fill_manual(
    name = NULL,
    values = c("Frei wählbar" = Fuego, "Buchung notwendig" = Brasa),
    labels = c("Frei wählbar" = "Frei nutzbar",
               "Buchung notwendig" = "Nur mit Buchung"),
    drop = FALSE
  ) +

  geom_label_repel(
    data = grill,
    aes(label = label, geometry = geometry),
    stat = "sf_coordinates",
    size = 4,
    fill = "white",
    color = "black",
    label.size = 0.25,
    label.padding = unit(0.2, "lines"),
    lineheight = 0.9,
    box.padding = 0.8,
    min.segment.length = 0,
    segment.color = "black",
    max.overlaps = Inf,
    seed = 2026
  ) +

  annotation_north_arrow(
    location = "tl",
    height = unit(2, "cm"),
    width = unit(2, "cm"),
    style = north_arrow_fancy_orienteering(
      line_col = "black",
      fill = "black",
      text_col = "black"
    )
  ) +

  annotation_scale(
    location = "bl",
    width_hint = 0.25,
    bar_cols = c("black", "black"),
    text_cex = 1.1,
    text_col = "black"
  ) +

  labs(
    title = "Grillen in Berlin, Deutschland",
    subtitle = paste0(
      "In Parks und Grünanlagen ist Grillen grundsätzlich verboten –\n",
      "erlaubt nur auf speziell ausgeschilderten Plätzen"
    ),
    caption = paste0(
      "Tag 1 - Punkte | #30DayMapChallenge 2026 | ",
      "Daten: Grillflächen, SenStadt Berlin - ",
      "OpenStreetMap - Natural Earth | K. Wiese"
    )
  ) +

  coord_sf(crs = crs_berlin, datum = 4326) +

  theme_minimal(base_size = 14) +
  theme(
    panel.grid = element_blank(),
    plot.title = element_text(face = "bold", size = 35, color = Texto, hjust = 0.5),
    plot.subtitle = element_text(size = 20, color = Texto, hjust = 0.5, lineheight = 1.1),
    plot.caption = element_text(size = 13, color = Texto, hjust = 0.5, lineheight = 1.1),
    axis.text = element_text(color = Texto),
    axis.title = element_blank(),
    legend.position = "bottom",
    legend.text = element_text(size = 15, color = Azul),
    plot.background = element_rect(fill = "white", color = NA)
  ) +

  # -----------------------------
  # INSERTAR INSET MAP
  # -----------------------------
annotation_custom(
  grob = ggplotGrob(inset_map),
  xmin = bbox_berlin["xmax"] - 0.22 * ancho,
  xmax = bbox_berlin["xmax"],
  ymin = bbox_berlin["ymax"] - 0.30 * alto,
  ymax = bbox_berlin["ymax"]
)

# ============================================================
# 7. EXPORTAR
# ============================================================
ggsave(
  filename = file.path(dia, "Tag01_Punkte_Grillen.png"),
  plot = p,
  width = 12,
  height = 10.5,
  dpi = 300
)
