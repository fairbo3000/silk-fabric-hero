import SilkCanvas from './components/SilkCanvas'
import './App.css'

export default function App() {
  return (
    <>
      {/* Full-screen silk fabric — fixed, behind everything */}
      <SilkCanvas />

      {/* Scrollable page content */}
      <div className="page">
        {/* Editorial hero text overlay */}
        <div className="hero-text">
          <span className="hero-eyebrow">Collection</span>
          <h1 className="hero-title">Soie Vivante</h1>
          <p className="hero-subtitle">
            A meditation on light, texture, and the quiet luxury of silk.
          </p>
        </div>
      </div>
    </>
  )
}
