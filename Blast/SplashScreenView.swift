import SwiftUI

struct Particle: Identifiable {
    let id: Int
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat
}

struct ParticleEffect: View {
    @State private var particles: [Particle] = []
    @State private var timer: Timer?
    let isAnimating: Bool
    
    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .scaleEffect(particle.scale)
                    .position(x: particle.x, y: particle.y)
                    .opacity(particle.scale)
            }
        }
        .onChange(of: isAnimating) { oldValue, newValue in
            if newValue {
                startEmitting()
            } else {
                stopEmitting()
            }
        }
    }
    
    private func startEmitting() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { _ in
            addParticle()
            removeOldParticles()
        }
    }
    
    private func stopEmitting() {
        timer?.invalidate()
        timer = nil
    }
    
    private func addParticle() {
        let randomX = CGFloat.random(in: -10...10)
        let newParticle = Particle(
            id: Int.random(in: 0...1000000),
            x: randomX,
            y: 0,
            scale: 1.0
        )
        particles.append(newParticle)
    }
    
    private func removeOldParticles() {
        particles = particles.filter { $0.scale > 0.1 }.map { particle in
            let newScale = max(0.1, particle.scale * 0.95)  // Ensure scale never goes below 0.1
            return Particle(
                id: particle.id,
                x: particle.x,
                y: particle.y + 5,
                scale: newScale
            )
        }
    }
}

struct SplashScreenView: View {
    @State private var isAnimating = false
    @State private var showMainContent = false
    @State private var mainChevronOffset: CGFloat = 0
    @State private var mainChevronScale: CGFloat = 1.0
    @State private var mainChevronOpacity: Double = 1.0
    @State private var textScale: CGFloat = 1.0
    
    var body: some View {
        if showMainContent {
            ContentView()
        } else {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Spacer()
                    
                    ZStack {
                        // Main chevron
                        Image(systemName: "chevron.forward.2")
                            .font(.system(size: 80))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(270))
                            .offset(y: mainChevronOffset)
                            .scaleEffect(mainChevronScale)
                            .opacity(mainChevronOpacity)
                        
                        // Particle effect
                        ParticleEffect(isAnimating: isAnimating)
                            .frame(width: 40, height: 100)
                            .offset(y: mainChevronOffset + 40)
                            .offset(x: 20, y: 40)
                            .opacity(mainChevronOpacity)
                    }
                    .frame(height: 120)
                    
                    Text("Blast")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(textScale)
                        .opacity(mainChevronOpacity)
                    
                    Spacer()
                }
                .padding()
                .onAppear {
                    // Initial delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeOut(duration: 0.5)) {
                            isAnimating = true
                        }
                        
                        // Start blast off sequence
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeIn(duration: 1.5)) {
                                // Main chevron flies up
                                mainChevronOffset = -UIScreen.main.bounds.height * 0.6
                                mainChevronScale = 0.5
                                mainChevronOpacity = 0
                                textScale = 1.5
                            }
                            
                            // Transition to main content
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                                withAnimation {
                                    showMainContent = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SplashScreenView()
} 