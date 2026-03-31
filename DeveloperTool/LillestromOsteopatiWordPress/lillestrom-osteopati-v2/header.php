<?php
/**
 * Header Template
 *
 * Outputs the HTML head and primary navigation.
 *
 * @package Lillestrom_Osteopati
 * @since   1.0.0
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}
?>
<!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
    <meta charset="<?php bloginfo( 'charset' ); ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>
<?php wp_body_open(); ?>

    <!-- ============ NAVIGATION ============ -->
    <nav class="navbar" id="navbar">
        <div class="container nav-container">
            <a href="<?php echo esc_url( home_url( '/' ) ); ?>#hjem" class="nav-logo">
                <img src="<?php echo esc_url( get_template_directory_uri() ); ?>/assets/images/logo.png" alt="<?php echo esc_attr( get_bloginfo( 'name' ) ); ?>" class="nav-logo-icon">
                <span class="logo-text">Lillestrøm<br><strong>Osteopati</strong></span>
            </a>
            <button class="nav-toggle" id="navToggle" aria-label="Meny">
                <span></span>
                <span></span>
                <span></span>
            </button>

            <?php if ( has_nav_menu( 'primary' ) ) : ?>
                <?php
                wp_nav_menu( array(
                    'theme_location' => 'primary',
                    'container'      => false,
                    'menu_class'     => 'nav-menu',
                    'menu_id'        => 'navMenu',
                    'walker'         => new LO_Nav_Walker(),
                    'fallback_cb'    => false,
                ) );
                ?>
            <?php else : ?>
                <ul class="nav-menu" id="navMenu">
                    <li><a href="#hjem" class="nav-link">Hjem</a></li>
                    <li><a href="#om-oss" class="nav-link">Om oss</a></li>
                    <li><a href="#osteopati" class="nav-link">Osteopati</a></li>
                    <li><a href="#behandlinger" class="nav-link">Behandlinger</a></li>
                    <li><a href="#behandlere" class="nav-link">Behandlere</a></li>
                    <li><a href="#forsikring" class="nav-link">Forsikring</a></li>
                    <li><a href="#bedrift" class="nav-link">Bedrift</a></li>
                    <li><a href="#priser" class="nav-link">Priser</a></li>
                    <li><a href="#faq" class="nav-link">FAQ</a></li>
                    <li><a href="#kontakt" class="nav-link">Kontakt</a></li>
                    <li><a href="#timebestilling" class="nav-link nav-cta">Bestill time</a></li>
                </ul>
            <?php endif; ?>

        </div>
    </nav>
