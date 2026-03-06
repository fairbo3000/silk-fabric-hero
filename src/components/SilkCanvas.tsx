import { useEffect, useRef } from 'react'
import * as THREE from 'three'
import Lenis from 'lenis'
import vertexShader from '../shaders/vertex.glsl'
import fragmentShader from '../shaders/fragment.glsl'

export default function SilkCanvas() {
  const containerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!containerRef.current) return

    // ── Helpers ───────────────────────────────────────────────
    const W = () => window.innerWidth || document.documentElement.clientWidth
    const H = () => window.innerHeight || document.documentElement.clientHeight

    // ── Scene ────────────────────────────────────────────────
    const scene = new THREE.Scene()
    const camera = new THREE.PerspectiveCamera(45, W() / H(), 0.01, 100)
    camera.position.z = 1.5

    // ── Renderer ─────────────────────────────────────────────

    const renderer = new THREE.WebGLRenderer({ antialias: false, alpha: true })
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    renderer.setSize(W(), H())
    renderer.setClearColor(0x000000, 0)
    containerRef.current.appendChild(renderer.domElement)

    // ── Lighting ─────────────────────────────────────────────
    scene.add(new THREE.AmbientLight(0xFFF8F0, 0.6))
    const dirLight = new THREE.DirectionalLight(0xFFFFFF, 0.8)
    dirLight.position.set(1, 2, 1)
    scene.add(dirLight)
    const rimLight = new THREE.DirectionalLight(0xFFEEDD, 0.3)
    rimLight.position.set(-2, 0, 0.5)
    scene.add(rimLight)

    // ── Geometry ─────────────────────────────────────────────
    const geometry = new THREE.PlaneGeometry(1.0, 1.0, 128, 256)

    // ── Uniforms ─────────────────────────────────────────────
    const uniforms = {
      uTime:           { value: 0 },
      uScrollVelocity: { value: 0 },
      uScrollPosition: { value: 0 },
      uMouseX:         { value: 0 },
      uResolution:     { value: new THREE.Vector2(W(), H()) },
      uWeaveScale:     { value: 200.0 },
    }

    const material = new THREE.ShaderMaterial({
      vertexShader,
      fragmentShader,
      transparent: true,
      side: THREE.DoubleSide,
      uniforms,
    })

    // ── Mesh sizing ───────────────────────────────────────────
    // FABRIC_MULTIPLIER: how many viewport-heights long the fabric is.
    // START_ABOVE: how many viewport-heights are already above the screen
    //   at scroll=0, so we start on the wavy mid-section, not the stiff top.
    // At scroll=1: bottom edge exits above viewport top — fabric fully gone.
    const FABRIC_MULTIPLIER = 5
    const START_ABOVE = 1.5   // vH units pre-lifted above viewport at scroll=0

    const getViewportDims = () => {
      const vH = 2 * Math.tan((45 * Math.PI) / 180 / 2) * 1.5
      const vW = vH * (W() / H())
      return { vW, vH }
    }

    // startY: top edge is START_ABOVE*vH above viewport top (+vH/2)
    //   top edge = startY + fabricH/2 = vH/2 + START_ABOVE*vH
    //   → startY = vH/2 + START_ABOVE*vH - fabricH/2
    // endY: bottom edge just exits viewport top
    //   bottom edge = endY - fabricH/2 = vH/2
    //   → endY = vH/2 + fabricH/2
    const getMeshPositions = (vH: number) => {
      const fabricH = vH * FABRIC_MULTIPLIER
      const startY = vH / 2 + START_ABOVE * vH - fabricH / 2
      const endY   = vH / 2 + fabricH / 2
      return { fabricH, startY, endY, scrollTravel: endY - startY }
    }

    const mesh = new THREE.Mesh(geometry, material)
    const { vW, vH } = getViewportDims()
    const { fabricH, startY } = getMeshPositions(vH)
    mesh.scale.set(vW * 0.75, fabricH, 1)
    mesh.position.y = startY
    scene.add(mesh)

    // ── Resize ───────────────────────────────────────────────
    const onResize = () => {
      const w = W()
      const h = H()
      camera.aspect = w / h
      camera.updateProjectionMatrix()
      renderer.setSize(w, h)
      uniforms.uResolution.value.set(w, h)
      const { vW: nW, vH: nH } = getViewportDims()
      const { fabricH: nFabricH, startY: nStartY, scrollTravel: nTravel } = getMeshPositions(nH)
      mesh.scale.set(nW * 0.75, nFabricH, 1)
      mesh.position.y = nStartY + uniforms.uScrollPosition.value * nTravel
    }
    window.addEventListener('resize', onResize)

    // ── Physics refs (no React state — direct uniform updates) ──
    const rawMouseX = { current: 0 }
    const smoothMouseX = { current: 0 }
    const targetVelocity = { current: 0 }
    const smoothVelocity = { current: 0 }
    const lastScrollTime = { current: 0 }

    // ── Mouse tracking ────────────────────────────────────────
    const onMouseMove = (e: MouseEvent) => {
      rawMouseX.current = (e.clientX / window.innerWidth) * 2 - 1
    }
    window.addEventListener('mousemove', onMouseMove)

    // ── Lenis scroll ──────────────────────────────────────────
    const lenis = new Lenis({
      duration: 1.4,
      easing: (t: number) => 1 - Math.pow(1 - t, 4),
    })

    // Scroll range: fabric travels (fabricH - vH) world units upward.
    // We compute this lazily in the tick using current scale.
    lenis.on('scroll', (e: { velocity: number; progress: number }) => {
      targetVelocity.current = e.velocity / 15
      lastScrollTime.current = performance.now()
      uniforms.uScrollPosition.value = e.progress
    })

    // ── RAF loop ──────────────────────────────────────────────
    let startTime = performance.now()
    let rafId: number
    let lastFrameTime = 0
    const TARGET_FPS = 30
    const FRAME_INTERVAL = 1000 / TARGET_FPS

    const tick = (time: number) => {
      rafId = requestAnimationFrame(tick)
      lenis.raf(time)

      if (time - lastFrameTime < FRAME_INTERVAL) return
      lastFrameTime = time

      // Time
      uniforms.uTime.value = (time - startTime) / 1000

      // Velocity decay
      const isIdle = performance.now() - lastScrollTime.current > 100
      const velTarget = isIdle ? 0 : targetVelocity.current
      smoothVelocity.current += (velTarget - smoothVelocity.current) * 0.12
      uniforms.uScrollVelocity.value = Math.max(-1, Math.min(1, smoothVelocity.current))

      // Mouse lerp
      smoothMouseX.current += (rawMouseX.current - smoothMouseX.current) * 0.12
      uniforms.uMouseX.value = smoothMouseX.current

      // Move mesh upward as user scrolls — the whole fabric lifts out.
      const { vH: curVH } = getViewportDims()
      const { startY: curStartY, scrollTravel: curTravel } = getMeshPositions(curVH)
      mesh.position.y = curStartY + uniforms.uScrollPosition.value * curTravel

      renderer.render(scene, camera)
    }

    rafId = requestAnimationFrame(tick)

    return () => {
      cancelAnimationFrame(rafId)
      lenis.destroy()
      window.removeEventListener('resize', onResize)
      window.removeEventListener('mousemove', onMouseMove)
      renderer.dispose()
      geometry.dispose()
      material.dispose()
      if (containerRef.current?.contains(renderer.domElement)) {
        containerRef.current.removeChild(renderer.domElement)
      }
    }
  }, [])

  return (
    <div
      ref={containerRef}
      style={{
        position: 'fixed',
        inset: 0,
        width: '100vw',
        height: '100vh',
        zIndex: 0,
        pointerEvents: 'none',
      }}
    />
  )
}
