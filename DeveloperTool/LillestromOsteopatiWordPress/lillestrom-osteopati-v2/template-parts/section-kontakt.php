<?php if (!defined('ABSPATH')) exit; ?>

<?php
$kontakt_label   = lo_get_option( 'lo_kontakt_label', 'Kontakt' );
$kontakt_title   = lo_get_option( 'lo_kontakt_title', 'Finn oss i Lillestrøm' );
$kontakt_form_h  = lo_get_option( 'lo_kontakt_form_heading', 'Send oss en melding' );
$address = lo_get_option( 'lo_contact_address', '' );
$phone   = lo_get_option( 'lo_contact_phone', '' );
$email   = lo_get_option( 'lo_contact_email', '' );
$hours   = lo_get_option( 'lo_contact_hours', '' );
$phone_stripped = preg_replace( '/\s+/', '', $phone );

// Contact items: only render if value is non-empty
$contact_items = array();
if ( ! empty( trim( $address ) ) ) {
    $contact_items[] = array( 'icon' => 'fa-map-marker-alt', 'heading' => 'Adresse', 'value' => nl2br( esc_html( $address ) ), 'raw' => true );
}
if ( ! empty( trim( $phone ) ) ) {
    $contact_items[] = array( 'icon' => 'fa-phone', 'heading' => 'Telefon', 'value' => '<a href="tel:' . esc_attr( $phone_stripped ) . '">' . esc_html( $phone ) . '</a>', 'raw' => true );
}
if ( ! empty( trim( $email ) ) ) {
    $contact_items[] = array( 'icon' => 'fa-envelope', 'heading' => 'E-post', 'value' => '<a href="mailto:' . esc_attr( $email ) . '">' . esc_html( $email ) . '</a>', 'raw' => true );
}
if ( ! empty( trim( $hours ) ) ) {
    $contact_items[] = array( 'icon' => 'fa-clock', 'heading' => 'Åpningstider', 'value' => nl2br( esc_html( $hours ) ), 'raw' => true );
}
?>

<section class="section section-light" id="kontakt">
    <div class="container">
        <div class="section-header">
            <?php if ( ! empty( trim( $kontakt_label ) ) ) : ?>
                <p class="section-label"><?php echo esc_html( $kontakt_label ); ?></p>
            <?php endif; ?>
            <?php if ( ! empty( trim( $kontakt_title ) ) ) : ?>
                <h2 class="section-title"><?php echo esc_html( $kontakt_title ); ?></h2>
            <?php endif; ?>
        </div>
        <div class="contact-grid">
            <?php if ( ! empty( $contact_items ) ) : ?>
                <div class="contact-info">
                    <?php foreach ( $contact_items as $item ) : ?>
                        <div class="contact-item">
                            <div class="contact-icon"><i class="fas <?php echo esc_attr( $item['icon'] ); ?>"></i></div>
                            <div>
                                <h4><?php echo esc_html( $item['heading'] ); ?></h4>
                                <p><?php echo $item['value']; /* Already escaped above */ ?></p>
                            </div>
                        </div>
                    <?php endforeach; ?>
                </div>
            <?php endif; ?>
            <div class="contact-form-wrap">
                <?php if ( ! empty( trim( $kontakt_form_h ) ) ) : ?>
                    <h3><?php echo esc_html( $kontakt_form_h ); ?></h3>
                <?php endif; ?>
                <?php
                $cf7_id = get_theme_mod( 'lo_cf7_form_id' );
                if ( $cf7_id && shortcode_exists( 'contact-form-7' ) ) {
                    echo do_shortcode( '[contact-form-7 id="' . intval( $cf7_id ) . '" html_class="contact-form"]' );
                } else {
                    $form_email = ! empty( trim( $email ) ) ? $email : 'post@lillestrom-osteopati.no';
                ?>
                    <form action="https://formsubmit.co/<?php echo esc_attr( $form_email ); ?>" method="POST" class="contact-form">
                        <input type="text" name="_honey" style="display:none">
                        <input type="hidden" name="_captcha" value="false">
                        <input type="hidden" name="_subject" value="Ny henvendelse fra nettsiden">
                        <div class="form-group">
                            <label>Navn <span class="required">*</span></label>
                            <input type="text" name="name" placeholder="Ditt fulle navn" required>
                        </div>
                        <div class="form-group">
                            <label>E-post <span class="required">*</span></label>
                            <input type="email" name="email" placeholder="din@epost.no" required>
                        </div>
                        <div class="form-group">
                            <label>Telefon</label>
                            <input type="tel" name="phone" placeholder="Valgfritt">
                        </div>
                        <div class="form-group">
                            <label>Melding <span class="required">*</span></label>
                            <textarea name="message" rows="5" placeholder="Beskriv kort hva du ønsker hjelp med..." required></textarea>
                        </div>
                        <button type="submit" class="btn btn-primary btn-submit">
                            <i class="fas fa-paper-plane"></i> Send melding
                        </button>
                    </form>
                <?php } ?>
            </div>
        </div>
    </div>
</section>
