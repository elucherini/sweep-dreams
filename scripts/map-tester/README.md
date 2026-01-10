# Map Tester

A simple web tool to visualize LineString and MultiLineString geometries on a Mapbox map.

## Usage

Start the server:

```bash
python scripts/map-tester/serve.py
```

This opens http://localhost:8000 in your browser.

## Input Formats

The tool accepts several input formats:

### Raw coordinates array (LineString)
```json
[[-122.4194, 37.7749], [-122.4094, 37.7849], [-122.3994, 37.7749]]
```

### Raw coordinates array (MultiLineString)
```json
[
  [[-122.4294, 37.7749], [-122.4194, 37.7849]],
  [[-122.4094, 37.7649], [-122.3994, 37.7549]]
]
```

### GeoJSON Geometry
```json
{
  "type": "LineString",
  "coordinates": [[-122.4194, 37.7749], [-122.4094, 37.7849]]
}
```

### GeoJSON Feature
```json
{
  "type": "Feature",
  "geometry": {
    "type": "LineString",
    "coordinates": [[-122.4194, 37.7749], [-122.4094, 37.7849]]
  }
}
```

### GeoJSON FeatureCollection
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [[-122.4194, 37.7749], [-122.4094, 37.7849]]
      }
    }
  ]
}
```

## Direct File Access

You can also open `index.html` directly in a browser (no server needed) - the Mapbox token is embedded.
