<?php
/**
 * Header Template
 *
 * @package OnePager
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

    <nav class="navbar" id="navbar">
        <div class="container nav-container">
            <a href="<?php echo esc_url( home_url( '/' ) ); ?>#home" class="nav-logo">
                <?php if ( has_custom_logo() ) : ?>
                    <?php
                    $custom_logo_id = get_theme_mod( 'custom_logo' );
                    $logo_url = wp_get_attachment_image_url( $custom_logo_id, 'full' );
                    ?>
                    <img src="<?php echo esc_url( $logo_url ); ?>" alt="<?php echo esc_attr( get_bloginfo( 'name' ) ); ?>" class="nav-logo-icon">
                <?php else : ?>
                    <img src="<?php echo esc_url( get_template_directory_uri() ); ?>/assets/images/logo.png" alt="<?php echo esc_attr( get_bloginfo( 'name' ) ); ?>" class="nav-logo-icon">
                <?php endif; ?>
                <span class="logo-text"><strong><?php echo esc_html( get_bloginfo( 'name' ) ); ?></strong></span>
            </a>
            <button class="nav-toggle" id="navToggle" aria-label="<?php esc_attr_e( 'Menu', 'onepager' ); ?>">
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
                    'walker'         => new OP_Nav_Walker(),
                    'fallback_cb'    => false,
                ) );
                ?>
            <?php else : ?>
                <ul class="nav-menu" id="navMenu">
                    <li><a href="#home" class="nav-link"><?php esc_html_e( 'Home', 'onepager' ); ?></a></li>
                    <li><a href="#about" class="nav-link"><?php esc_html_e( 'About', 'onepager' ); ?></a></li>
                    <li><a href="#expertise" class="nav-link"><?php esc_html_e( 'Expertise', 'onepager' ); ?></a></li>
                    <li><a href="#services" class="nav-link"><?php esc_html_e( 'Services', 'onepager' ); ?></a></li>
                    <li><a href="#team" class="nav-link"><?php esc_html_e( 'Team', 'onepager' ); ?></a></li>
                    <li><a href="#partners" class="nav-link"><?php esc_html_e( 'Partners', 'onepager' ); ?></a></li>
                    <li><a href="#pricing" class="nav-link"><?php esc_html_e( 'Pricing', 'onepager' ); ?></a></li>
                    <li><a href="#faq" class="nav-link"><?php esc_html_e( 'FAQ', 'onepager' ); ?></a></li>
                    <li><a href="#contact" class="nav-link"><?php esc_html_e( 'Contact', 'onepager' ); ?></a></li>
                    <li><a href="#cta" class="nav-link nav-cta"><?php esc_html_e( 'Get Started', 'onepager' ); ?></a></li>
                </ul>
            <?php endif; ?>

        </div>
    </nav>
