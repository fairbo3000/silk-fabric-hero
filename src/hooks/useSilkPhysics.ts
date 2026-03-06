/**
 * useSilkPhysics
 *
 * Drives the physical simulation values for the silk fabric hero:
 *   - scrollVelocity  — normalised -1..1, lerped from Lenis scroll events, decays to 0 when idle
 *   - scrollPosition  — normalised 0..1, representing progress through the total scrollable height
 *   - mouseX          — normalised -1..1, smoothly lerped from raw mouse X position
 *
 * Uses Lenis for buttery smooth scroll and its own RAF integration so all
 * value updates happen in a single, well-ordered animation loop.
 */

import { useEffect, useRef, useState } from 'react'
import Lenis from 'lenis'

const VELOCITY_LERP = 0.12
const VELOCITY_SENSITIVITY = 15
const MOUSE_LERP = 0.05
const IDLE_THRESHOLD_MS = 100

interface SilkPhysics {
  scrollVelocity: number
  scrollPosition: number
  mouseX: number
}

export function useSilkPhysics(): SilkPhysics {
  const [scrollVelocity, setScrollVelocity] = useState(0)
  const [scrollPosition, setScrollPosition] = useState(0)
  const [mouseX, setMouseX] = useState(0)

  // Mutable refs — avoids stale closures inside the RAF loop
  const rawMouseXRef = useRef(0)
  const currentMouseXRef = useRef(0)
  const targetVelocityRef = useRef(0)
  const currentVelocityRef = useRef(0)
  const lastScrollEventRef = useRef<number>(0)
  const rafIdRef = useRef<number>(0)

  useEffect(() => {
    const lenis = new Lenis({
      duration: 1.4,
      easing: (t: number) => 1 - Math.pow(1 - t, 4),
    })

    // Capture raw velocity from Lenis on each scroll event
    lenis.on('scroll', (e: { velocity: number }) => {
      targetVelocityRef.current = e.velocity / VELOCITY_SENSITIVITY
      lastScrollEventRef.current = performance.now()
    })

    // Mouse move handler — store normalised raw value
    const onMouseMove = (e: MouseEvent): void => {
      rawMouseXRef.current = (e.clientX / window.innerWidth) * 2 - 1
    }
    window.addEventListener('mousemove', onMouseMove)

    // RAF loop using Lenis's own integration
    function raf(time: number): void {
      lenis.raf(time)

      const now = performance.now()
      const isIdle = now - lastScrollEventRef.current > IDLE_THRESHOLD_MS

      // Lerp velocity: decay to 0 when idle, otherwise track target
      const target = isIdle ? 0 : targetVelocityRef.current
      currentVelocityRef.current +=
        (target - currentVelocityRef.current) * VELOCITY_LERP
      const clampedVelocity = Math.max(
        -1,
        Math.min(1, currentVelocityRef.current)
      )

      // Lerp mouseX toward raw position
      currentMouseXRef.current +=
        (rawMouseXRef.current - currentMouseXRef.current) * MOUSE_LERP

      // Scroll position: guard against division by zero when page isn't scrollable
      const limit = lenis.limit
      const position = limit > 0 ? lenis.scroll / limit : 0

      setScrollVelocity(clampedVelocity)
      setScrollPosition(position)
      setMouseX(currentMouseXRef.current)

      rafIdRef.current = requestAnimationFrame(raf)
    }

    rafIdRef.current = requestAnimationFrame(raf)

    return () => {
      cancelAnimationFrame(rafIdRef.current)
      lenis.destroy()
      window.removeEventListener('mousemove', onMouseMove)
    }
  }, [])

  return { scrollVelocity, scrollPosition, mouseX }
}
