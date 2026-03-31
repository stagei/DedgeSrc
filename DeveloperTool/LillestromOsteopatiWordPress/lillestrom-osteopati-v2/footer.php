<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$footer_tagline    = lo_get_option( 'lo_footer_tagline', 'Profesjonell osteopatisk behandling i hjertet av Lillestrøm. Autorisert helsepersonell siden 2022.' );
$contact_address   = lo_get_option( 'lo_contact_address', "Lillestrøm sentrum\nLillestrøm, Norge" );
$contact_email     = lo_get_option( 'lo_contact_email', 'post@lillestrom-osteopati.no' );
$footer_copyright  = lo_get_option( 'lo_footer_copyright', 'Lillestrøm Osteopati. Alle rettigheter reservert.' );
$footer_membership = lo_get_option( 'lo_footer_membership', 'Norsk Osteopatforbund' );
$footer_member_url = lo_get_option( 'lo_footer_membership_url', 'https://osteopati.org' );

$address_lines      = explode( "\n", $contact_address );
$address_first_line = trim( $address_lines[0] );
?>

    <!-- ============ FOOTER ============ -->
    <footer class="footer">
        <div class="container">
            <div class="footer-grid">
                <div class="footer-brand">
                    <div class="footer-logo">
                        <img src="<?php echo esc_url( get_template_directory_uri() ); ?>/assets/images/logo.png" alt="<?php echo esc_attr( get_bloginfo( 'name' ) ); ?>" class="footer-logo-icon">
                        <span class="logo-text">Lillestrøm<br><strong>Osteopati</strong></span>
                    </div>
                    <p><?php echo esc_html( $footer_tagline ); ?></p>
                </div>
                <div class="footer-links">
                    <h4>Sider</h4>
                    <ul>
                        <li><a href="#hjem">Hjem</a></li>
                        <li><a href="#om-oss">Om oss</a></li>
                        <li><a href="#osteopati">Osteopati</a></li>
                        <li><a href="#behandlinger">Behandlinger</a></li>
                        <li><a href="#forsikring">Forsikring</a></li>
                        <li><a href="#bedrift">Bedrift</a></li>
                    </ul>
                </div>
                <div class="footer-links">
                    <h4>Praktisk info</h4>
                    <ul>
                        <li><a href="#priser">Priser</a></li>
                        <li><a href="#kontakt">Kontakt</a></li>
                        <li><a href="#timebestilling">Bestill time</a></li>
                    </ul>
                </div>
                <div class="footer-contact">
                    <h4>Kontakt oss</h4>
                    <p><?php echo esc_html( $address_first_line ); ?></p>
                    <p><a href="mailto:<?php echo esc_attr( $contact_email ); ?>"><?php echo esc_html( $contact_email ); ?></a></p>
                </div>
            </div>
            <div class="footer-bottom">
                <p>&copy; <?php echo esc_html( date( 'Y' ) ); ?> <?php echo esc_html( $footer_copyright ); ?></p>
                <?php if ( $footer_membership ) : ?>
                    <p>Medlem av <a href="<?php echo esc_url( $footer_member_url ); ?>" target="_blank" rel="noopener"><?php echo esc_html( $footer_membership ); ?></a></p>
                <?php endif; ?>
            </div>
        </div>
    </footer>

    <?php wp_footer(); ?>
</body>
</html>
