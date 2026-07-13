// ===========================
// Mobile Menu Toggle
// ===========================

/**
 * Initialize mobile menu toggle
 */
function initializeMobileMenu() {
    const hamburger = document.getElementById('hamburger');
    const navMenu = document.getElementById('navMenu');
    const navLinks = document.querySelectorAll('.nav-link');

    if (hamburger) {
        hamburger.addEventListener('click', (e) => {
            e.stopPropagation();
            hamburger.classList.toggle('active');
            navMenu.classList.toggle('active');
        });
    }

    // Close menu when a link is clicked
    navLinks.forEach(link => {
        link.addEventListener('click', () => {
            hamburger?.classList.remove('active');
            navMenu?.classList.remove('active');
        });
    });

    // Close menu when clicking outside
    document.addEventListener('click', (e) => {
        if (!e.target.closest('.navbar')) {
            hamburger?.classList.remove('active');
            navMenu?.classList.remove('active');
        }
    });
}

// ===========================
// Utility Functions
// ===========================

/**
 * Scroll to a specific section by ID
 * @param {string} sectionId - The ID of the section to scroll to
 */
function scrollToSection(sectionId) {
    const element = document.getElementById(sectionId);
    if (element) {
        element.scrollIntoView({ behavior: 'smooth' });
    }
}

/**
 * Handle contact support button click
 */
function contactSupport() {
    // This can be replaced with actual contact functionality
    // For now, it opens an email client
    window.location.href = 'mailto:support@dayung.app?subject=Dayung%20Support%20Request';
}

// ===========================
// Scroll Animations
// ===========================

/**
 * Intersection Observer for scroll animations
 */
const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -100px 0px'
};

const observer = new IntersectionObserver(function(entries) {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.classList.add('fade-in');
            observer.unobserve(entry.target);
        }
    });
}, observerOptions);

// Observe all feature items and role cards
document.addEventListener('DOMContentLoaded', function() {
    // Initialize mobile menu
    initializeMobileMenu();

    const animatedElements = document.querySelectorAll(
        '.feature-item, .role-card, .highlight-card, .security-item, .tech-column'
    );
    
    animatedElements.forEach(element => {
        observer.observe(element);
    });

    // Add smooth scroll behavior to navigation links
    addSmoothScrollBehavior();

    // Initialize any interactive elements
    initializeInteractiveElements();
});

/**
 * Add smooth scroll behavior to all navigation links
 */
function addSmoothScrollBehavior() {
    const navLinks = document.querySelectorAll('a[href^="#"]');
    
    navLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            const href = this.getAttribute('href');
            if (href !== '#' && document.querySelector(href)) {
                e.preventDefault();
                const targetElement = document.querySelector(href);
                targetElement.scrollIntoView({ behavior: 'smooth' });
            }
        });
    });
}

/**
 * Initialize interactive elements
 */
function initializeInteractiveElements() {
    // Add hover effects to buttons
    const buttons = document.querySelectorAll('.btn, .download-btn, .nav-link');
    
    buttons.forEach(button => {
        button.addEventListener('mouseenter', function() {
            this.style.transition = 'all 0.3s ease';
        });
    });

    // Handle window resize for responsive behavior
    handleResponsiveBehavior();
}

/**
 * Handle responsive behavior
 */
function handleResponsiveBehavior() {
    const navMenu = document.querySelector('.nav-menu');
    let lastScrollTop = 0;
    const navbar = document.querySelector('.navbar');

    // Optional: Hide navbar on scroll down, show on scroll up
    // Uncomment if desired
    /*
    window.addEventListener('scroll', () => {
        const currentScroll = window.pageYOffset || document.documentElement.scrollTop;

        if (currentScroll > lastScrollTop && currentScroll > 100) {
            navbar.style.transform = 'translateY(-100%)';
            navbar.style.transition = 'transform 0.3s ease';
        } else {
            navbar.style.transform = 'translateY(0)';
            navbar.style.transition = 'transform 0.3s ease';
        }

        lastScrollTop = currentScroll <= 0 ? 0 : currentScroll;
    });
    */
}

// ===========================
// Add CSS for animations
// ===========================

const style = document.createElement('style');
style.textContent = `
    @keyframes fadeIn {
        from {
            opacity: 0;
            transform: translateY(20px);
        }
        to {
            opacity: 1;
            transform: translateY(0);
        }
    }

    .fade-in {
        animation: fadeIn 0.6s ease forwards;
    }

    .feature-item, .role-card, .highlight-card, .security-item, .tech-column {
        opacity: 0;
    }
`;
document.head.appendChild(style);

// ===========================
// Analytics & Tracking
// ===========================

/**
 * Track user interactions
 */
function trackEvent(eventName, eventData = {}) {
    console.log(`Event: ${eventName}`, eventData);
}

// Track button clicks
document.addEventListener('click', function(e) {
    if (e.target.matches('.btn, .download-btn')) {
        const buttonText = e.target.textContent;
        trackEvent('button_click', { button: buttonText });
    }
});

// ===========================
// Performance Optimization
// ===========================

/**
 * Lazy load images
 */
function initializeLazyLoading() {
    if ('IntersectionObserver' in window) {
        const imageObserver = new IntersectionObserver((entries, observer) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    const img = entry.target;
                    img.src = img.dataset.src;
                    img.classList.add('loaded');
                    observer.unobserve(img);
                }
            });
        });

        document.querySelectorAll('img[data-src]').forEach(img => imageObserver.observe(img));
    }
}

document.addEventListener('DOMContentLoaded', initializeLazyLoading);

// ===========================
// Scroll to Top Function
// ===========================

/**
 * Scroll to top functionality
 */
function scrollToTop() {
    window.scrollTo({
        top: 0,
        behavior: 'smooth'
    });
}

// ===========================
// Form Validation
// ===========================

/**
 * Validate email format
 */
function isValidEmail(email) {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
}

// ===========================
// Export functions for external use
// ===========================

window.dayungApp = {
    scrollToSection,
    contactSupport,
    trackEvent,
    scrollToTop,
    isValidEmail
};
