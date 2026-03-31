<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$prosess_label = lo_get_option( 'lo_prosess_label', 'Slik jobber vi' );
$prosess_title = lo_get_option( 'lo_prosess_title', 'Din første konsultasjon' );

$lo_step_defaults = array(
    1 => array( 'title' => 'Samtale', 'text' => 'Vi starter med en grundig gjennomgang av din sykehistorie, nåværende plager og hva du ønsker hjelp med.' ),
    2 => array( 'title' => 'Undersøkelse', 'text' => 'En systematisk undersøkelse av kroppen for å finne årsaken til plagene dine — ikke bare symptomene.' ),
    3 => array( 'title' => 'Behandling', 'text' => 'Skånsom og effektiv manuell behandling tilpasset dine behov, med teknikker som mobilisering, manipulasjon og bløtvevsbehandling.' ),
    4 => array( 'title' => 'Oppfølging', 'text' => 'Du får råd om øvelser og tiltak du kan gjøre selv, samt en plan for videre behandling ved behov.' ),
);

// Build steps: only render if title is non-empty
$steps = array();
$step_num = 1;
for ( $i = 1; $i <= 4; $i++ ) {
    $title = lo_get_option( 'lo_prosess_step' . $i . '_title', $lo_step_defaults[ $i ]['title'] );
    if ( ! empty( trim( $title ) ) ) {
        $steps[] = array(
            'number' => $step_num,
            'title'  => $title,
            'text'   => lo_get_option( 'lo_prosess_step' . $i . '_text', $lo_step_defaults[ $i ]['text'] ),
        );
        $step_num++;
    }
}
?>

<?php if ( ! empty( $steps ) ) : ?>
<section class="section section-dark">
    <div class="container">
        <div class="section-header">
            <?php if ( ! empty( trim( $prosess_label ) ) ) : ?>
                <p class="section-label light"><?php echo esc_html( $prosess_label ); ?></p>
            <?php endif; ?>
            <?php if ( ! empty( trim( $prosess_title ) ) ) : ?>
                <h2 class="section-title light"><?php echo esc_html( $prosess_title ); ?></h2>
            <?php endif; ?>
        </div>
        <div class="process-grid">
            <?php foreach ( $steps as $step ) : ?>
                <div class="process-step">
                    <div class="process-number"><?php echo esc_html( $step['number'] ); ?></div>
                    <h4><?php echo esc_html( $step['title'] ); ?></h4>
                    <?php if ( ! empty( trim( $step['text'] ) ) ) : ?>
                        <p><?php echo esc_html( $step['text'] ); ?></p>
                    <?php endif; ?>
                </div>
            <?php endforeach; ?>
        </div>
    </div>
</section>
<?php endif; ?>
