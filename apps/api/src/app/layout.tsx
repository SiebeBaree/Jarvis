// API-only service — this root layout exists solely because the App Router
// requires one to build. No UI is served from this app.
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
