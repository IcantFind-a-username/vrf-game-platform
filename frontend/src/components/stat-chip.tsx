export function StatChip({ label, value }: { label: string; value: string }) {
  return (
    <div className="stat-chip">
      <div className="stat-label">{label}</div>
      <div className="stat-value">{value}</div>
    </div>
  );
}
