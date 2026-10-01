// The app's severity bands, mirrored.
//
// These must stay in step with `MetricKind.bands` in ios/Shared/Models/MetricKind.swift. They
// are duplicated rather than derived because a push has to be decided server-side, with the
// app closed, and Postgres has no view of the app's model. If you change a threshold there,
// change it here.

export type MetricKey = "co2" | "temperature" | "humidity" | "light";

interface Band {
  /** Exclusive upper bound; the last band is open-ended. */
  upper: number;
  label: string;
  /** 0 fine, 3 bad. Humidity and temperature are bad at both ends, so this is a rank, not a
   *  position on the scale. */
  severity: number;
}

const BANDS: Record<MetricKey, Band[]> = {
  co2: [
    { upper: 800, label: "Fresh", severity: 0 },
    { upper: 1200, label: "Stuffy", severity: 1 },
    { upper: 1600, label: "Poor", severity: 2 },
    { upper: Infinity, label: "Bad", severity: 3 },
  ],
  humidity: [
    { upper: 20, label: "Very dry", severity: 3 },
    { upper: 30, label: "Dry", severity: 2 },
    { upper: 40, label: "A bit dry", severity: 1 },
    { upper: 60, label: "Comfortable", severity: 0 },
    { upper: 70, label: "Humid", severity: 1 },
    { upper: 80, label: "Very humid", severity: 2 },
    { upper: Infinity, label: "Damp", severity: 3 },
  ],
  light: [
    { upper: 20, label: "Dark", severity: 2 },
    { upper: 80, label: "Dim", severity: 1 },
    { upper: Infinity, label: "Bright", severity: 0 },
  ],
  temperature: [
    { upper: 16, label: "Cold", severity: 2 },
    { upper: 19, label: "Cool", severity: 1 },
    { upper: 25, label: "Comfortable", severity: 0 },
    { upper: 28, label: "Warm", severity: 1 },
    { upper: Infinity, label: "Hot", severity: 2 },
  ],
};

export const METRICS: MetricKey[] = ["co2", "humidity", "temperature", "light"];

export const TITLES: Record<MetricKey, string> = {
  co2: "CO₂",
  temperature: "Temperature",
  humidity: "Humidity",
  light: "Light",
};

export const UNITS: Record<MetricKey, string> = {
  co2: "ppm",
  temperature: "°C",
  humidity: "%",
  light: "lux",
};

export function bandFor(metric: MetricKey, value: number): Band {
  const bands = BANDS[metric];
  return bands.find((band) => value < band.upper) ?? bands[bands.length - 1];
}

export function format(metric: MetricKey, value: number): string {
  const digits = metric === "temperature" ? 1 : 0;
  return value.toFixed(digits);
}
