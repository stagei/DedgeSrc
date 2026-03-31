<?php
/**
 * Lillestrøm Osteopati Theme Customizer
 *
 * Registers all Customizer panels, sections, settings, and controls
 * for the Lillestrøm Osteopati theme.
 *
 * @package Lillestrom_Osteopati
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

/**
 * Register Customizer settings.
 *
 * @param WP_Customize_Manager $wp_customize The Customizer manager instance.
 */
function lo_customize_register( $wp_customize ) {

    // =========================================================================
    // Panel: Lillestrøm Osteopati
    // =========================================================================
    $wp_customize->add_panel( 'lo_panel', array(
        'title'    => __( 'Lillestrøm Osteopati', 'lillestrom-osteopati-v2' ),
        'priority' => 30,
    ) );

    // =========================================================================
    // Section 1: Hero
    // =========================================================================
    $wp_customize->add_section( 'lo_hero', array(
        'title' => __( 'Hero', 'lillestrom-osteopati-v2' ),
        'panel' => 'lo_panel',
    ) );

    // Hero — Badge 1
    $wp_customize->add_setting( 'lo_hero_badge1', array( 'default' => 'Autorisert helsepersonell', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_hero_badge1', array( 'label' => __( 'Badge 1 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_hero', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_hero_badge1_icon', array( 'default' => 'fa-user-md', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_hero_badge1_icon', array( 'label' => __( 'Badge 1 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_hero', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );

    // Hero — Badge 2
    $wp_customize->add_setting( 'lo_hero_badge2', array( 'default' => 'Ingen ventetid', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_hero_badge2', array( 'label' => __( 'Badge 2 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_hero', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_hero_badge2_icon', array( 'default' => 'fa-clock', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_hero_badge2_icon', array( 'label' => __( 'Badge 2 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_hero', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );

    // Hero — Badge 3
    $wp_customize->add_setting( 'lo_hero_badge3', array( 'default' => 'Ingen henvisning nødvendig', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_hero_badge3', array( 'label' => __( 'Badge 3 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_hero', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_hero_badge3_icon', array( 'default' => 'fa-file-medical', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_hero_badge3_icon', array( 'label' => __( 'Badge 3 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_hero', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );

    // Hero — Subtitle
    $wp_customize->add_setting( 'lo_hero_subtitle', array(
        'default'           => 'Velkommen til',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_hero_subtitle', array(
        'label'   => __( 'Undertittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_hero',
        'type'    => 'text',
    ) );

    // Hero — Title
    $wp_customize->add_setting( 'lo_hero_title', array(
        'default'           => 'Lillestrøm Osteopati',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_hero_title', array(
        'label'   => __( 'Tittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_hero',
        'type'    => 'text',
    ) );

    // Hero — Description
    $wp_customize->add_setting( 'lo_hero_description', array(
        'default'           => 'Profesjonell osteopatisk behandling i hjertet av Lillestrøm. Vi hjelper deg med smerter, stivhet og nedsatt funksjon — med kroppen som helhet.',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_hero_description', array(
        'label'   => __( 'Beskrivelse', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_hero',
        'type'    => 'textarea',
    ) );

    // Hero — Primary Button
    $wp_customize->add_setting( 'lo_hero_btn_primary', array(
        'default'           => 'Bestill time',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_hero_btn_primary', array(
        'label'   => __( 'Primærknapp tekst', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_hero',
        'type'    => 'text',
    ) );

    // Hero — Secondary Button
    $wp_customize->add_setting( 'lo_hero_btn_secondary', array(
        'default'           => 'Les mer om osteopati',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_hero_btn_secondary', array(
        'label'   => __( 'Sekundærknapp tekst', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_hero',
        'type'    => 'text',
    ) );

    // =========================================================================
    // Section 2: Om oss (About)
    // =========================================================================
    $wp_customize->add_section( 'lo_about', array(
        'title' => __( 'Om oss', 'lillestrom-osteopati-v2' ),
        'panel' => 'lo_panel',
    ) );

    // About — Lead text
    $wp_customize->add_setting( 'lo_about_lead', array(
        'default'           => 'Lillestrøm Osteopati tilbyr helhetlig osteopatisk behandling for hele familien. Som autorisert helsepersonell kombinerer vi grundig klinisk undersøkelse med skånsomme, manuelle teknikker tilpasset dine behov.',
        'sanitize_callback' => 'wp_kses_post',
    ) );
    $wp_customize->add_control( 'lo_about_lead', array(
        'label'   => __( 'Ingress', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_about',
        'type'    => 'textarea',
    ) );

    // About — Text paragraph 1
    $wp_customize->add_setting( 'lo_about_text1', array(
        'default'           => 'Osteopater har siden 1. mai 2022 vært autorisert helsepersonell i Norge, underlagt kravene fra Helsedirektoratet. Du trenger ingen henvisning fra lege — vi er primærkontakter i førstelinjetjenesten.',
        'sanitize_callback' => 'wp_kses_post',
    ) );
    $wp_customize->add_control( 'lo_about_text1', array(
        'label'   => __( 'Avsnitt 1', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_about',
        'type'    => 'textarea',
    ) );

    // About — Text paragraph 2
    $wp_customize->add_setting( 'lo_about_text2', array(
        'default'           => 'Vi har flere dyktige medarbeidere med stor kapasitet, og kan tilby time på kort varsel. Vi tar oss god tid til hver pasient, og fokuserer på å finne de underliggende årsakene til plagene dine — ikke bare symptomene.',
        'sanitize_callback' => 'wp_kses_post',
    ) );
    $wp_customize->add_control( 'lo_about_text2', array(
        'label'   => __( 'Avsnitt 2', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_about',
        'type'    => 'textarea',
    ) );

    // About — Stat 1 Number
    $wp_customize->add_setting( 'lo_about_stat1_number', array(
        'default'           => '4-årig',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_about_stat1_number', array(
        'label'   => __( 'Statistikk 1 — Tall', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_about',
        'type'    => 'text',
    ) );

    // About — Stat 1 Label
    $wp_customize->add_setting( 'lo_about_stat1_label', array(
        'default'           => 'Høyskoleutdanning',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_about_stat1_label', array(
        'label'   => __( 'Statistikk 1 — Etikett', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_about',
        'type'    => 'text',
    ) );

    // About — Stat 2 Number
    $wp_customize->add_setting( 'lo_about_stat2_number', array(
        'default'           => '45–60',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_about_stat2_number', array(
        'label'   => __( 'Statistikk 2 — Tall', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_about',
        'type'    => 'text',
    ) );

    // About — Stat 2 Label
    $wp_customize->add_setting( 'lo_about_stat2_label', array(
        'default'           => 'Min. per konsultasjon',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_about_stat2_label', array(
        'label'   => __( 'Statistikk 2 — Etikett', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_about',
        'type'    => 'text',
    ) );

    // About — Stat 3 Number
    $wp_customize->add_setting( 'lo_about_stat3_number', array(
        'default'           => '100%',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_about_stat3_number', array(
        'label'   => __( 'Statistikk 3 — Tall', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_about',
        'type'    => 'text',
    ) );

    // About — Stat 3 Label
    $wp_customize->add_setting( 'lo_about_stat3_label', array(
        'default'           => 'Fokus på deg',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_about_stat3_label', array(
        'label'   => __( 'Statistikk 3 — Etikett', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_about',
        'type'    => 'text',
    ) );

    // =========================================================================
    // Section 3: Osteopati
    // =========================================================================
    $wp_customize->add_section( 'lo_osteopati', array(
        'title' => __( 'Osteopati', 'lillestrom-osteopati-v2' ),
        'panel' => 'lo_panel',
    ) );

    // Osteopati — Subtitle
    $wp_customize->add_setting( 'lo_osteo_subtitle', array(
        'default'           => 'En osteopat er autorisert helsepersonell med bred kunnskap om hvordan fysiske, psykiske og sosiale faktorer henger sammen og påvirker helsen din.',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_osteo_subtitle', array(
        'label'   => __( 'Undertittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_osteopati',
        'type'    => 'textarea',
    ) );

    // Osteopati — Intro paragraph 1
    $wp_customize->add_setting( 'lo_osteo_intro1', array(
        'default'           => 'En osteopat skiller seg fra andre manuelle behandlere ved at osteopaten ser <strong>helheten</strong> i pasientens plager. Vi finner <strong>årsaken</strong> til symptomene — ikke bare behandler symptomene. Dette gjennomføres gjennom grundig undersøkelse og behandling som har som mål å finne funksjons- og bevegelsesforstyrrelser og å normalisere disse. Osteopaten behandler både akutte og kroniske lidelser.',
        'sanitize_callback' => 'wp_kses_post',
    ) );
    $wp_customize->add_control( 'lo_osteo_intro1', array(
        'label'   => __( 'Intro — Avsnitt 1', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_osteopati',
        'type'    => 'textarea',
    ) );

    // Osteopati — Intro paragraph 2
    $wp_customize->add_setting( 'lo_osteo_intro2', array(
        'default'           => 'Hos Lillestrøm Osteopati tilpasser vi behandlingen til dine behov. Vi kombinerer manuelle teknikker med veiledning og motivasjon — enten målet er å lindre akutte plager eller hjelpe deg til å mestre langvarige utfordringer.',
        'sanitize_callback' => 'wp_kses_post',
    ) );
    $wp_customize->add_control( 'lo_osteo_intro2', array(
        'label'   => __( 'Intro — Avsnitt 2', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_osteopati',
        'type'    => 'textarea',
    ) );

    // Osteopati — Card 1
    $wp_customize->add_setting( 'lo_osteo_card1_icon', array( 'default' => 'fa-bone', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_osteo_card1_icon', array( 'label' => __( 'Kort 1 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_osteopati', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );
    $wp_customize->add_setting( 'lo_osteo_card1_title', array( 'default' => 'Parietal osteopati', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_osteo_card1_title', array( 'label' => __( 'Kort 1 — Tittel', 'lillestrom-osteopati-v2' ), 'section' => 'lo_osteopati', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_osteo_card1_text', array( 'default' => 'Behandling av muskel- og skjelettsystemet med teknikker som leddmobilisering, muskeltøyning, muskelenergiteknikker (MET) og manipulasjon.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_osteo_card1_text', array( 'label' => __( 'Kort 1 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_osteopati', 'type' => 'textarea' ) );

    // Osteopati — Card 2
    $wp_customize->add_setting( 'lo_osteo_card2_icon', array( 'default' => 'fa-lungs', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_osteo_card2_icon', array( 'label' => __( 'Kort 2 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_osteopati', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );
    $wp_customize->add_setting( 'lo_osteo_card2_title', array( 'default' => 'Visceral osteopati', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_osteo_card2_title', array( 'label' => __( 'Kort 2 — Tittel', 'lillestrom-osteopati-v2' ), 'section' => 'lo_osteopati', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_osteo_card2_text', array( 'default' => 'Skånsomme teknikker rettet mot indre organer og deres bindevevssystem, for å stimulere økt bevegelse, sirkulasjon og nervefunksjon.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_osteo_card2_text', array( 'label' => __( 'Kort 2 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_osteopati', 'type' => 'textarea' ) );

    // Osteopati — Card 3
    $wp_customize->add_setting( 'lo_osteo_card3_icon', array( 'default' => 'fa-brain', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_osteo_card3_icon', array( 'label' => __( 'Kort 3 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_osteopati', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );
    $wp_customize->add_setting( 'lo_osteo_card3_title', array( 'default' => 'Kranial osteopati', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_osteo_card3_title', array( 'label' => __( 'Kort 3 — Tittel', 'lillestrom-osteopati-v2' ), 'section' => 'lo_osteopati', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_osteo_card3_text', array( 'default' => 'Svært forsiktige teknikker rettet mot hodet, ryggmargen og nervesystemet — basert på de subtile bevegelsene mellom skallens knokler.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_osteo_card3_text', array( 'label' => __( 'Kort 3 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_osteopati', 'type' => 'textarea' ) );

    // Osteopati — Who Title
    $wp_customize->add_setting( 'lo_osteo_who_title', array(
        'default'           => 'Hvem passer osteopati for?',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_osteo_who_title', array(
        'label'   => __( 'Hvem passer det for — Tittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_osteopati',
        'type'    => 'text',
    ) );

    // Osteopati — Who Text 1
    $wp_customize->add_setting( 'lo_osteo_who_text1', array(
        'default'           => 'Osteopati passer for deg som ønsker en helhetlig tilnærming til helse og velvære. Vi behandler pasienter i alle aldre med smerter, skader eller sykdom i muskler og skjelett. Behandlingen tar utgangspunkt i sammenhengen mellom hverdagen, kroppen og plagene, og målet er å styrke pasientens evne til å hjelpe seg selv.',
        'sanitize_callback' => 'wp_kses_post',
    ) );
    $wp_customize->add_control( 'lo_osteo_who_text1', array(
        'label'   => __( 'Hvem passer det for — Avsnitt 1', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_osteopati',
        'type'    => 'textarea',
    ) );

    // Osteopati — Who Text 2
    $wp_customize->add_setting( 'lo_osteo_who_text2', array(
        'default'           => 'Vi behandler et bredt spekter av muskel- og leddsmerter — fra idrettsskader og belastningsskader til kroniske plager. Behandlingen kan både lindre akutte smerter og bidra til å forebygge fremtidige skader.',
        'sanitize_callback' => 'wp_kses_post',
    ) );
    $wp_customize->add_control( 'lo_osteo_who_text2', array(
        'label'   => __( 'Hvem passer det for — Avsnitt 2', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_osteopati',
        'type'    => 'textarea',
    ) );

    // =========================================================================
    // Section 4: Behandlinger
    // =========================================================================
    $wp_customize->add_section( 'lo_behandlinger', array(
        'title' => __( 'Behandlinger', 'lillestrom-osteopati-v2' ),
        'panel' => 'lo_panel',
    ) );

    // Behandlinger — Subtitle
    $wp_customize->add_setting( 'lo_behandlinger_subtitle', array(
        'default'           => 'Osteopati kan hjelpe med et bredt spekter av plager. Her er noen av de vanligste tilstandene vi behandler.',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_behandlinger_subtitle', array(
        'label'   => __( 'Undertittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_behandlinger',
        'type'    => 'textarea',
    ) );

    // =========================================================================
    // Section 5: Prosess (Din første konsultasjon)
    // =========================================================================
    $wp_customize->add_section( 'lo_prosess', array(
        'title' => __( 'Prosess', 'lillestrom-osteopati-v2' ),
        'panel' => 'lo_panel',
    ) );

    // Step 1
    $wp_customize->add_setting( 'lo_prosess_step1_title', array(
        'default'           => 'Samtale',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_prosess_step1_title', array(
        'label'   => __( 'Steg 1 — Tittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_prosess',
        'type'    => 'text',
    ) );

    $wp_customize->add_setting( 'lo_prosess_step1_text', array(
        'default'           => 'Vi starter med en grundig samtale om dine plager, sykehistorie og hva du ønsker hjelp med.',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_prosess_step1_text', array(
        'label'   => __( 'Steg 1 — Tekst', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_prosess',
        'type'    => 'textarea',
    ) );

    // Step 2
    $wp_customize->add_setting( 'lo_prosess_step2_title', array(
        'default'           => 'Undersøkelse',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_prosess_step2_title', array(
        'label'   => __( 'Steg 2 — Tittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_prosess',
        'type'    => 'text',
    ) );

    $wp_customize->add_setting( 'lo_prosess_step2_text', array(
        'default'           => 'En klinisk undersøkelse for å kartlegge bevegelse, smerte og funksjon i de aktuelle områdene.',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_prosess_step2_text', array(
        'label'   => __( 'Steg 2 — Tekst', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_prosess',
        'type'    => 'textarea',
    ) );

    // Step 3
    $wp_customize->add_setting( 'lo_prosess_step3_title', array(
        'default'           => 'Behandling',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_prosess_step3_title', array(
        'label'   => __( 'Steg 3 — Tittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_prosess',
        'type'    => 'text',
    ) );

    $wp_customize->add_setting( 'lo_prosess_step3_text', array(
        'default'           => 'Skånsomme, manuelle teknikker tilpasset dine behov — med kroppen som helhet i fokus.',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_prosess_step3_text', array(
        'label'   => __( 'Steg 3 — Tekst', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_prosess',
        'type'    => 'textarea',
    ) );

    // Step 4
    $wp_customize->add_setting( 'lo_prosess_step4_title', array(
        'default'           => 'Oppfølging',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_prosess_step4_title', array(
        'label'   => __( 'Steg 4 — Tittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_prosess',
        'type'    => 'text',
    ) );

    $wp_customize->add_setting( 'lo_prosess_step4_text', array(
        'default'           => 'Du får øvelser og råd med hjem, og vi legger en plan for videre behandling ved behov.',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_prosess_step4_text', array(
        'label'   => __( 'Steg 4 — Tekst', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_prosess',
        'type'    => 'textarea',
    ) );

    // =========================================================================
    // Section 6: Forsikring
    // =========================================================================
    $wp_customize->add_section( 'lo_forsikring', array(
        'title' => __( 'Forsikring', 'lillestrom-osteopati-v2' ),
        'panel' => 'lo_panel',
    ) );

    // Forsikring — Subtitle
    $wp_customize->add_setting( 'lo_forsikring_subtitle', array(
        'default'           => 'Dersom du har helseforsikring privat eller via arbeidsgiver, kan det være at forsikringsselskapet dekker utgiftene til behandling. Undersøk med din arbeidsgiver og ditt forsikringsselskap. Vi kan i mange tilfeller fakturere direkte.',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_forsikring_subtitle', array(
        'label'   => __( 'Undertittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_forsikring',
        'type'    => 'textarea',
    ) );

    // Forsikring — Companies (comma-separated)
    $wp_customize->add_setting( 'lo_forsikring_companies', array(
        'default'           => 'If / Vertikal Helse, Storebrand, Gjensidige, Tryg, DNB, SpareBank 1',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_forsikring_companies', array(
        'label'       => __( 'Forsikringsselskaper', 'lillestrom-osteopati-v2' ),
        'description' => __( 'Kommaseparert liste over forsikringsselskaper.', 'lillestrom-osteopati-v2' ),
        'section'     => 'lo_forsikring',
        'type'        => 'textarea',
    ) );

    // Forsikring — Note
    $wp_customize->add_setting( 'lo_forsikring_note', array(
        'default'           => 'Har du et annet forsikringsselskap? Ta kontakt — vi hjelper deg gjerne med å finne ut om din forsikring dekker behandlingen.',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_forsikring_note', array(
        'label'   => __( 'Merknad', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_forsikring',
        'type'    => 'textarea',
    ) );

    // =========================================================================
    // Section 7: Priser
    // =========================================================================
    $wp_customize->add_section( 'lo_priser', array(
        'title' => __( 'Priser', 'lillestrom-osteopati-v2' ),
        'panel' => 'lo_panel',
    ) );

    // Price 1
    $wp_customize->add_setting( 'lo_price1_title', array(
        'default'           => 'Ny pasient / Førstekonsultasjon',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_price1_title', array(
        'label'   => __( 'Pris 1 — Tittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_priser',
        'type'    => 'text',
    ) );

    $wp_customize->add_setting( 'lo_price1_desc', array(
        'default'           => 'Inkluderer samtale, undersøkelse og behandling (ca. 60 min)',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_price1_desc', array(
        'label'   => __( 'Pris 1 — Beskrivelse', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_priser',
        'type'    => 'textarea',
    ) );

    $wp_customize->add_setting( 'lo_price1_amount', array(
        'default'           => 'Pris kommer',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_price1_amount', array(
        'label'   => __( 'Pris 1 — Beløp', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_priser',
        'type'    => 'text',
    ) );

    // Price 2
    $wp_customize->add_setting( 'lo_price2_title', array(
        'default'           => 'Oppfølgende behandling',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_price2_title', array(
        'label'   => __( 'Pris 2 — Tittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_priser',
        'type'    => 'text',
    ) );

    $wp_customize->add_setting( 'lo_price2_desc', array(
        'default'           => 'Behandling for eksisterende pasienter (ca. 45 min)',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_price2_desc', array(
        'label'   => __( 'Pris 2 — Beskrivelse', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_priser',
        'type'    => 'textarea',
    ) );

    $wp_customize->add_setting( 'lo_price2_amount', array(
        'default'           => 'Pris kommer',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_price2_amount', array(
        'label'   => __( 'Pris 2 — Beløp', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_priser',
        'type'    => 'text',
    ) );

    // Price 3
    $wp_customize->add_setting( 'lo_price3_title', array(
        'default'           => 'Barn (under 16 år)',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_price3_title', array(
        'label'   => __( 'Pris 3 — Tittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_priser',
        'type'    => 'text',
    ) );

    $wp_customize->add_setting( 'lo_price3_desc', array(
        'default'           => 'Tilpasset konsultasjon og behandling for barn',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_price3_desc', array(
        'label'   => __( 'Pris 3 — Beskrivelse', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_priser',
        'type'    => 'textarea',
    ) );

    $wp_customize->add_setting( 'lo_price3_amount', array(
        'default'           => 'Pris kommer',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_price3_amount', array(
        'label'   => __( 'Pris 3 — Beløp', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_priser',
        'type'    => 'text',
    ) );

    // =========================================================================
    // Section 8: Kontakt
    // =========================================================================
    $wp_customize->add_section( 'lo_kontakt', array(
        'title' => __( 'Kontakt', 'lillestrom-osteopati-v2' ),
        'panel' => 'lo_panel',
    ) );

    // Kontakt — Address
    $wp_customize->add_setting( 'lo_contact_address', array(
        'default'           => "Lillestrøm sentrum\nLillestrøm, Norge",
        'sanitize_callback' => 'wp_kses_post',
    ) );
    $wp_customize->add_control( 'lo_contact_address', array(
        'label'   => __( 'Adresse', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_kontakt',
        'type'    => 'textarea',
    ) );

    // Kontakt — Phone
    $wp_customize->add_setting( 'lo_contact_phone', array(
        'default'           => '+47 99 100 111',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_contact_phone', array(
        'label'   => __( 'Telefon', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_kontakt',
        'type'    => 'text',
    ) );

    // Kontakt — Email
    $wp_customize->add_setting( 'lo_contact_email', array(
        'default'           => 'post@lillestrom-osteopati.no',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_contact_email', array(
        'label'   => __( 'E-post', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_kontakt',
        'type'    => 'text',
    ) );

    // Kontakt — Opening Hours
    $wp_customize->add_setting( 'lo_contact_hours', array(
        'default'           => "Mandag – Fredag: 08:00 – 18:00\nLørdag: Etter avtale\nSøndag: Stengt",
        'sanitize_callback' => 'wp_kses_post',
    ) );
    $wp_customize->add_control( 'lo_contact_hours', array(
        'label'   => __( 'Åpningstider', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_kontakt',
        'type'    => 'textarea',
    ) );

    // =========================================================================
    // Section 9: CTA (Timebestilling)
    // =========================================================================
    $wp_customize->add_section( 'lo_cta', array(
        'title' => __( 'Timebestilling / CTA', 'lillestrom-osteopati-v2' ),
        'panel' => 'lo_panel',
    ) );

    // CTA — Title
    $wp_customize->add_setting( 'lo_cta_title', array(
        'default'           => 'Klar for å ta vare på kroppen din?',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_cta_title', array(
        'label'   => __( 'Tittel', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_cta',
        'type'    => 'text',
    ) );

    // CTA — Text
    $wp_customize->add_setting( 'lo_cta_text', array(
        'default'           => 'Bestill time i dag — ingen henvisning nødvendig. Vi tar oss tid til å finne de underliggende årsakene til plagene dine.',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_cta_text', array(
        'label'   => __( 'Tekst', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_cta',
        'type'    => 'textarea',
    ) );

    // CTA — Phone
    $wp_customize->add_setting( 'lo_cta_phone', array(
        'default'           => '99 100 111',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_cta_phone', array(
        'label'   => __( 'Telefonnummer', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_cta',
        'type'    => 'text',
    ) );

    // =========================================================================
    // Section 10: Footer
    // =========================================================================
    $wp_customize->add_section( 'lo_footer', array(
        'title' => __( 'Footer', 'lillestrom-osteopati-v2' ),
        'panel' => 'lo_panel',
    ) );

    // Footer — Tagline
    $wp_customize->add_setting( 'lo_footer_tagline', array(
        'default'           => 'Profesjonell osteopatisk behandling i hjertet av Lillestrøm. Autorisert helsepersonell siden 2022.',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_footer_tagline', array(
        'label'   => __( 'Tagline', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_footer',
        'type'    => 'textarea',
    ) );

    // Footer — Copyright
    $wp_customize->add_setting( 'lo_footer_copyright', array(
        'default'           => 'Lillestrøm Osteopati. Alle rettigheter reservert.',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_footer_copyright', array(
        'label'   => __( 'Copyright-tekst', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_footer',
        'type'    => 'text',
    ) );

    // Footer — Membership text
    $wp_customize->add_setting( 'lo_footer_membership', array(
        'default'           => 'Norsk Osteopatforbund',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'lo_footer_membership', array(
        'label'   => __( 'Medlemskap — Organisasjon', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_footer',
        'type'    => 'text',
    ) );

    // Footer — Membership URL
    $wp_customize->add_setting( 'lo_footer_membership_url', array(
        'default'           => 'https://osteopati.org',
        'sanitize_callback' => 'esc_url_raw',
    ) );
    $wp_customize->add_control( 'lo_footer_membership_url', array(
        'label'   => __( 'Medlemskap — URL', 'lillestrom-osteopati-v2' ),
        'section' => 'lo_footer',
        'type'    => 'url',
    ) );

    // =========================================================================
    // Section headers (label + title) for all sections
    // =========================================================================

    // About — Section header
    $wp_customize->add_setting( 'lo_about_label', array( 'default' => 'Om oss', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_about_label', array( 'label' => __( 'Seksjonsetikett', 'lillestrom-osteopati-v2' ), 'section' => 'lo_about', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'lo_about_title', array( 'default' => 'Din helse i trygge hender', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_about_title', array( 'label' => __( 'Seksjonsoverskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_about', 'type' => 'text', 'priority' => 2 ) );

    // Osteopati — Section header
    $wp_customize->add_setting( 'lo_osteo_label', array( 'default' => 'Osteopati', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_osteo_label', array( 'label' => __( 'Seksjonsetikett', 'lillestrom-osteopati-v2' ), 'section' => 'lo_osteopati', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'lo_osteo_title', array( 'default' => 'Hva er osteopati?', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_osteo_title', array( 'label' => __( 'Seksjonsoverskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_osteopati', 'type' => 'text', 'priority' => 2 ) );

    // Behandlinger — Section header
    $wp_customize->add_setting( 'lo_behandlinger_label', array( 'default' => 'Behandlinger', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_behandlinger_label', array( 'label' => __( 'Seksjonsetikett', 'lillestrom-osteopati-v2' ), 'section' => 'lo_behandlinger', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'lo_behandlinger_title', array( 'default' => 'Hva kan vi hjelpe deg med?', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_behandlinger_title', array( 'label' => __( 'Seksjonsoverskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_behandlinger', 'type' => 'text', 'priority' => 2 ) );

    // Prosess — Section header
    $wp_customize->add_setting( 'lo_prosess_label', array( 'default' => 'Slik jobber vi', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_prosess_label', array( 'label' => __( 'Seksjonsetikett', 'lillestrom-osteopati-v2' ), 'section' => 'lo_prosess', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'lo_prosess_title', array( 'default' => 'Din første konsultasjon', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_prosess_title', array( 'label' => __( 'Seksjonsoverskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_prosess', 'type' => 'text', 'priority' => 2 ) );

    // Behandlere — Section header (shown under Behandlinger section in Customizer)
    $wp_customize->add_setting( 'lo_behandlere_label', array( 'default' => 'Behandlere', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_behandlere_label', array( 'label' => __( 'Behandlere — Seksjonsetikett', 'lillestrom-osteopati-v2' ), 'section' => 'lo_behandlinger', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_behandlere_title', array( 'default' => 'Møt våre behandlere', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_behandlere_title', array( 'label' => __( 'Behandlere — Overskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_behandlinger', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_behandlere_education_heading', array( 'default' => 'Utdanning', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_behandlere_education_heading', array( 'label' => __( 'Behandlere — Utdanning-overskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_behandlinger', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_behandlere_interests_heading', array( 'default' => 'Faglige interesseområder', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_behandlere_interests_heading', array( 'label' => __( 'Behandlere — Interesseområder-overskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_behandlinger', 'type' => 'text' ) );

    // Forsikring — Section header + steps
    $wp_customize->add_setting( 'lo_forsikring_label', array( 'default' => 'Forsikring', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_forsikring_label', array( 'label' => __( 'Seksjonsetikett', 'lillestrom-osteopati-v2' ), 'section' => 'lo_forsikring', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'lo_forsikring_title', array( 'default' => 'Behandlingsforsikring', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_forsikring_title', array( 'label' => __( 'Seksjonsoverskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_forsikring', 'type' => 'text', 'priority' => 2 ) );
    $wp_customize->add_setting( 'lo_forsikring_steps_heading', array( 'default' => 'Slik bruker du forsikringen din', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_forsikring_steps_heading', array( 'label' => __( 'Steg — Overskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_forsikring', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_forsikring_step1_title', array( 'default' => 'Kontakt forsikringsselskapet', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_forsikring_step1_title', array( 'label' => __( 'Steg 1 — Tittel', 'lillestrom-osteopati-v2' ), 'section' => 'lo_forsikring', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_forsikring_step1_text', array( 'default' => 'Ring forsikringsselskapet ditt og meld inn sak. Du får et saksnummer.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_forsikring_step1_text', array( 'label' => __( 'Steg 1 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_forsikring', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'lo_forsikring_step2_title', array( 'default' => 'Bestill time hos oss', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_forsikring_step2_title', array( 'label' => __( 'Steg 2 — Tittel', 'lillestrom-osteopati-v2' ), 'section' => 'lo_forsikring', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_forsikring_step2_text', array( 'default' => 'Oppgi saksnummeret når du bestiller time, så ordner vi resten.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_forsikring_step2_text', array( 'label' => __( 'Steg 2 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_forsikring', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'lo_forsikring_step3_title', array( 'default' => 'Vi fakturerer direkte', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_forsikring_step3_title', array( 'label' => __( 'Steg 3 — Tittel', 'lillestrom-osteopati-v2' ), 'section' => 'lo_forsikring', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_forsikring_step3_text', array( 'default' => 'I de fleste tilfeller kan vi sende regningen rett til forsikringsselskapet.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_forsikring_step3_text', array( 'label' => __( 'Steg 3 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_forsikring', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'lo_forsikring_companies_heading', array( 'default' => 'Vi samarbeider med blant annet', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_forsikring_companies_heading', array( 'label' => __( 'Selskaper — Overskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_forsikring', 'type' => 'text' ) );

    // Priser — Section header + notes
    $wp_customize->add_setting( 'lo_priser_label', array( 'default' => 'Priser', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_priser_label', array( 'label' => __( 'Seksjonsetikett', 'lillestrom-osteopati-v2' ), 'section' => 'lo_priser', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'lo_priser_title', array( 'default' => 'Våre priser', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_priser_title', array( 'label' => __( 'Seksjonsoverskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_priser', 'type' => 'text', 'priority' => 2 ) );
    $wp_customize->add_setting( 'lo_priser_badge', array( 'default' => 'Vanligst', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_priser_badge', array( 'label' => __( 'Badge-tekst (populær pris)', 'lillestrom-osteopati-v2' ), 'section' => 'lo_priser', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_priser_helfo_note', array( 'default' => 'Osteopati er ikke dekket av Helfo. Behandling betales privat eller via behandlingsforsikring.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_priser_helfo_note', array( 'label' => __( 'Helfo-merknad', 'lillestrom-osteopati-v2' ), 'section' => 'lo_priser', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'lo_priser_cancel_note', array( 'default' => 'Vi ber om at avbestilling skjer senest 24 timer før avtalt time.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_priser_cancel_note', array( 'label' => __( 'Avbestillingsmerknad', 'lillestrom-osteopati-v2' ), 'section' => 'lo_priser', 'type' => 'textarea' ) );

    // Kontakt — Section header + headings
    $wp_customize->add_setting( 'lo_kontakt_label', array( 'default' => 'Kontakt', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_kontakt_label', array( 'label' => __( 'Seksjonsetikett', 'lillestrom-osteopati-v2' ), 'section' => 'lo_kontakt', 'type' => 'text', 'priority' => 1 ) );
    $wp_customize->add_setting( 'lo_kontakt_title', array( 'default' => 'Finn oss i Lillestrøm', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_kontakt_title', array( 'label' => __( 'Seksjonsoverskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_kontakt', 'type' => 'text', 'priority' => 2 ) );
    $wp_customize->add_setting( 'lo_kontakt_form_heading', array( 'default' => 'Send oss en melding', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_kontakt_form_heading', array( 'label' => __( 'Skjema-overskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_kontakt', 'type' => 'text' ) );

    // FAQ — Section header
    $wp_customize->add_setting( 'lo_faq_label', array( 'default' => 'Spørsmål og svar', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_faq_label', array( 'label' => __( 'FAQ — Seksjonsetikett', 'lillestrom-osteopati-v2' ), 'section' => 'lo_cta', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_faq_title', array( 'default' => 'Ofte stilte spørsmål', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_faq_title', array( 'label' => __( 'FAQ — Overskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_cta', 'type' => 'text' ) );

    // CTA — Extra fields
    $wp_customize->add_setting( 'lo_cta_btn_call', array( 'default' => 'Ring', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_cta_btn_call', array( 'label' => __( 'Ringeknapp — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_cta', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_cta_btn_email', array( 'default' => 'Send e-post', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_cta_btn_email', array( 'label' => __( 'E-postknapp — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_cta', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_cta_trust_note', array( 'default' => 'Autorisert helsepersonell — underlagt Helsedirektoratets krav', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_cta_trust_note', array( 'label' => __( 'Tillitsmerknad', 'lillestrom-osteopati-v2' ), 'section' => 'lo_cta', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_cta_trust_icon', array( 'default' => 'fa-shield-alt', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_cta_trust_icon', array( 'label' => __( 'Tillitsmerknad — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_cta', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );

    // =========================================================================
    // Section 11: Bedrift
    // =========================================================================
    $wp_customize->add_section( 'lo_bedrift', array(
        'title' => __( 'Bedrift', 'lillestrom-osteopati-v2' ),
        'panel' => 'lo_panel',
    ) );

    $wp_customize->add_setting( 'lo_bedrift_label', array( 'default' => 'Bedrift', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_label', array( 'label' => __( 'Seksjonsetikett', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_bedrift_title', array( 'default' => 'Osteopati for bedrifter', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_title', array( 'label' => __( 'Seksjonsoverskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_bedrift_subtitle', array( 'default' => 'Vi ønsker å tilrettelegge for å bedre helsen til de ansatte — gjennom grundig undersøkelse, behandling og forebyggende tiltak tilpasset hver enkelt.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_subtitle', array( 'label' => __( 'Undertittel', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'textarea' ) );
    // Bedrift — Benefits (individual text + icon pairs, max 6)
    $wp_customize->add_setting( 'lo_bedrift_benefit1_text', array( 'default' => 'Redusert sykefravær', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_benefit1_text', array( 'label' => __( 'Fordel 1 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_bedrift_benefit1_icon', array( 'default' => 'fa-calendar-check', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_benefit1_icon', array( 'label' => __( 'Fordel 1 — Ikon', 'lillestrom-osteopati-v2' ), 'description' => __( 'Tøm teksten for å skjule denne fordelen.', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );
    $wp_customize->add_setting( 'lo_bedrift_benefit2_text', array( 'default' => 'Økt trivsel', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_benefit2_text', array( 'label' => __( 'Fordel 2 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_bedrift_benefit2_icon', array( 'default' => 'fa-smile', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_benefit2_icon', array( 'label' => __( 'Fordel 2 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );
    $wp_customize->add_setting( 'lo_bedrift_benefit3_text', array( 'default' => 'Reduserte kostnader', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_benefit3_text', array( 'label' => __( 'Fordel 3 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_bedrift_benefit3_icon', array( 'default' => 'fa-piggy-bank', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_benefit3_icon', array( 'label' => __( 'Fordel 3 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );
    $wp_customize->add_setting( 'lo_bedrift_benefit4_text', array( 'default' => 'Økt yteevne og effektivitet', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_benefit4_text', array( 'label' => __( 'Fordel 4 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_bedrift_benefit4_icon', array( 'default' => 'fa-chart-line', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_benefit4_icon', array( 'label' => __( 'Fordel 4 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );
    $wp_customize->add_setting( 'lo_bedrift_benefit5_text', array( 'default' => 'Godt arbeidsmiljø', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_benefit5_text', array( 'label' => __( 'Fordel 5 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_bedrift_benefit5_icon', array( 'default' => 'fa-users', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_benefit5_icon', array( 'label' => __( 'Fordel 5 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );
    $wp_customize->add_setting( 'lo_bedrift_benefit6_text', array( 'default' => '', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_benefit6_text', array( 'label' => __( 'Fordel 6 — Tekst (valgfri)', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_bedrift_benefit6_icon', array( 'default' => 'fa-check', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_benefit6_icon', array( 'label' => __( 'Fordel 6 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );

    $wp_customize->add_setting( 'lo_bedrift_description', array( 'default' => 'Gjennom tester, samtaler og kartlegging av bedriften kommer vi fram til en hensiktsmessig og kostnadseffektiv løsning. Vi kan forhindre at ansatte med plager forsvinner ut i sykemelding, forebygge overbelastning og skader hos friske arbeidstakere, og hjelpe allerede sykemeldte tilbake i arbeid.', 'sanitize_callback' => 'wp_kses_post' ) );
    $wp_customize->add_control( 'lo_bedrift_description', array( 'label' => __( 'Hovedtekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'textarea' ) );

    // Bedrift — Service cards (with icons)
    $wp_customize->add_setting( 'lo_bedrift_card1_icon', array( 'default' => 'fa-building', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_card1_icon', array( 'label' => __( 'Tjeneste 1 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );
    $wp_customize->add_setting( 'lo_bedrift_card1_title', array( 'default' => 'Behandling på arbeidsplassen', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_card1_title', array( 'label' => __( 'Tjeneste 1 — Tittel', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_bedrift_card1_text', array( 'default' => 'Vi kommer til bedriften med faste intervaller og behandler de ansatte på arbeidsplassen. Vi har med eget utstyr og trenger kun et rom.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_card1_text', array( 'label' => __( 'Tjeneste 1 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'lo_bedrift_card2_icon', array( 'default' => 'fa-receipt', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_card2_icon', array( 'label' => __( 'Tjeneste 2 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );
    $wp_customize->add_setting( 'lo_bedrift_card2_title', array( 'default' => 'Fleksibel betaling', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_card2_title', array( 'label' => __( 'Tjeneste 2 — Tittel', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_bedrift_card2_text', array( 'default' => 'Bedriften dekker deler eller hele behandlingssummen. Vi sender faktura ved månedsslutt, eller etter avtale. Eventuell egenandel kan trekkes av lønnen.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_card2_text', array( 'label' => __( 'Tjeneste 2 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'lo_bedrift_card3_icon', array( 'default' => 'fa-percentage', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_card3_icon', array( 'label' => __( 'Tjeneste 3 — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );
    $wp_customize->add_setting( 'lo_bedrift_card3_title', array( 'default' => 'Skattefradrag', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_card3_title', array( 'label' => __( 'Tjeneste 3 — Tittel', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_bedrift_card3_text', array( 'default' => 'Forebyggende behandling som foregår hos bedriften gir skattefradrag. Den ansatte skal ikke belastes med fordelsbeskatning.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_card3_text', array( 'label' => __( 'Tjeneste 3 — Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'textarea' ) );

    // Bedrift — Statistics (with icon)
    $wp_customize->add_setting( 'lo_bedrift_stat_icon', array( 'default' => 'fa-exclamation-triangle', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_stat_icon', array( 'label' => __( 'Statistikk — Ikon', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'select', 'choices' => lo_get_icon_choices() ) );
    $wp_customize->add_setting( 'lo_bedrift_stat_heading', array( 'default' => 'Sykefravær er en stor utgift', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_stat_heading', array( 'label' => __( 'Statistikk — Overskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_bedrift_stat1', array( 'default' => 'Muskel- og skjelettlidelser er den vanligste årsaken til lengre sykefravær.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_stat1', array( 'label' => __( 'Statistikk 1', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'lo_bedrift_stat2', array( 'default' => 'SINTEF har regnet ut at bedriften taper i gjennomsnitt 13.000 kroner per uke ved sykefravær av en ansatt. Lønnsutgifter kommer i tillegg.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_stat2', array( 'label' => __( 'Statistikk 2', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'lo_bedrift_stat3', array( 'default' => 'Statistikk fra NAV viser over 10,4 millioner sykefraværsdager som følge av muskel- og skjelettlidelser — tilsvarende over 2 millioner ukeverk.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_stat3', array( 'label' => __( 'Statistikk 3', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'textarea' ) );

    // Bedrift — CTA
    $wp_customize->add_setting( 'lo_bedrift_cta_text', array( 'default' => 'Kontakt Lillestrøm Osteopati Bedrift for tilbud. Vi kommer gjerne ut til bedriften for en presentasjon om hva vi kan tilby.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_cta_text', array( 'label' => __( 'CTA-tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'lo_bedrift_cta_button', array( 'default' => 'Kontakt oss for tilbud', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_bedrift_cta_button', array( 'label' => __( 'CTA-knapp tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_bedrift', 'type' => 'text' ) );

    // =========================================================================
    // Section 12: Takk (Thank You)
    // =========================================================================
    $wp_customize->add_section( 'lo_takk', array(
        'title' => __( 'Takk-side', 'lillestrom-osteopati-v2' ),
        'panel' => 'lo_panel',
    ) );

    $wp_customize->add_setting( 'lo_takk_heading', array( 'default' => 'Takk for din henvendelse!', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_takk_heading', array( 'label' => __( 'Overskrift', 'lillestrom-osteopati-v2' ), 'section' => 'lo_takk', 'type' => 'text' ) );
    $wp_customize->add_setting( 'lo_takk_text', array( 'default' => 'Vi har mottatt meldingen din og vil svare deg så snart som mulig — vanligvis innen en virkedag.', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_takk_text', array( 'label' => __( 'Tekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_takk', 'type' => 'textarea' ) );
    $wp_customize->add_setting( 'lo_takk_button', array( 'default' => 'Tilbake til forsiden', 'sanitize_callback' => 'sanitize_text_field' ) );
    $wp_customize->add_control( 'lo_takk_button', array( 'label' => __( 'Knappetekst', 'lillestrom-osteopati-v2' ), 'section' => 'lo_takk', 'type' => 'text' ) );
}
add_action( 'customize_register', 'lo_customize_register' );
