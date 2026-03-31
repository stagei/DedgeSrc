<?php
/**
 * Theme Setup — Initial Content Population
 *
 * Runs on theme activation (after_switch_theme) to auto-populate the site
 * with a static front page, primary navigation menu, sample staff posts,
 * FAQ items, and a Contact Form 7 contact form.
 *
 * Every section checks for existing content before creating anything,
 * making the routine safe to run more than once.
 *
 * @package Lillestrøm_Osteopati
 * @since   1.0.0
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit; // Prevent direct access.
}

add_action( 'after_switch_theme', 'lo_populate_initial_content' );

/**
 * One-time migration: if the theme is already active but defaults were never
 * saved (upgraded from an earlier version), persist them on the next page load.
 * The sentinel key 'lo_defaults_saved' is set after the first run.
 */
add_action( 'init', 'lo_maybe_save_defaults_once' );
function lo_maybe_save_defaults_once() {
	if ( false === get_theme_mod( 'lo_defaults_saved' ) ) {
		lo_setup_default_theme_mods();
		set_theme_mod( 'lo_defaults_saved', true );
	}
}

/**
 * Populate the site with initial content on theme activation.
 *
 * @return void
 */
function lo_populate_initial_content() {

	/* ==================================================================
	 * 0. Save all Customizer defaults to the database
	 *    (get_theme_mod() only uses the add_setting() default inside
	 *     the Customizer preview — on the frontend it needs the values
	 *     to be stored in the DB so that template parts render content.)
	 * ================================================================ */

	lo_setup_default_theme_mods();

	/* ==================================================================
	 * 1. Create the "Hjem" (Home) page and set it as the static front page
	 * ================================================================ */

	lo_setup_front_page();

	/* ==================================================================
	 * 2. Create the primary navigation menu "Hovedmeny"
	 * ================================================================ */

	lo_setup_primary_menu();

	/* ==================================================================
	 * 3. Create initial Behandler (staff) posts
	 * ================================================================ */

	lo_setup_behandler_posts();

	/* ==================================================================
	 * 4. Create initial FAQ posts
	 * ================================================================ */

	lo_setup_faq_posts();

	/* ==================================================================
	 * 5. Create initial Behandling (treatment) cards
	 * ================================================================ */

	lo_setup_behandling_posts();

	/* ==================================================================
	 * 6. Create Contact Form 7 form (if CF7 plugin is active)
	 * ================================================================ */

	lo_setup_cf7_form();
}


/* --------------------------------------------------------------------------
 * 0. Customizer Defaults — persist to DB on first activation
 *
 * WordPress get_theme_mod() only falls back to the 'default' registered in
 * add_setting() during the Customizer *preview*. On the real frontend it
 * returns the explicit $default argument passed to get_theme_mod() — which
 * in most template parts is ''.  Saving the defaults once ensures every
 * section renders its content immediately after activation.
 * ----------------------------------------------------------------------- */

/**
 * Persist all Customizer defaults to the database so that the frontend
 * template parts receive the correct values via get_theme_mod().
 *
 * Only sets a value if it has not been saved yet (false === get_theme_mod()).
 *
 * @return void
 */
function lo_setup_default_theme_mods() {

	$defaults = array(

		// ── Hero ────────────────────────────────────────────────────
		'lo_hero_subtitle'       => 'Velkommen til',
		'lo_hero_title'          => 'Lillestrøm Osteopati',
		'lo_hero_description'    => 'Profesjonell osteopatisk behandling i hjertet av Lillestrøm. Vi hjelper deg med smerter, stivhet og nedsatt funksjon — med kroppen som helhet.',
		'lo_hero_btn_primary'    => 'Bestill time',
		'lo_hero_btn_secondary'  => 'Les mer om osteopati',
		'lo_hero_badge1'         => 'Autorisert helsepersonell',
		'lo_hero_badge1_icon'    => 'fa-user-md',
		'lo_hero_badge2'         => 'Ingen ventetid',
		'lo_hero_badge2_icon'    => 'fa-clock',
		'lo_hero_badge3'         => 'Ingen henvisning nødvendig',
		'lo_hero_badge3_icon'    => 'fa-file-medical',

		// ── Om oss (About) ─────────────────────────────────────────
		'lo_about_label'         => 'Om oss',
		'lo_about_title'         => 'Din helse i trygge hender',
		'lo_about_lead'          => 'Lillestrøm Osteopati tilbyr helhetlig osteopatisk behandling for hele familien. Som autorisert helsepersonell kombinerer vi grundig klinisk undersøkelse med skånsomme, manuelle teknikker tilpasset dine behov.',
		'lo_about_text1'         => 'Osteopater har siden 1. mai 2022 vært autorisert helsepersonell i Norge, underlagt kravene fra Helsedirektoratet. Du trenger ingen henvisning fra lege — vi er primærkontakter i førstelinjetjenesten.',
		'lo_about_text2'         => 'Vi har flere dyktige medarbeidere med stor kapasitet, og kan tilby time på kort varsel. Vi tar oss god tid til hver pasient, og fokuserer på å finne de underliggende årsakene til plagene dine — ikke bare symptomene.',
		'lo_about_stat1_number'  => '4-årig',
		'lo_about_stat1_label'   => 'Høyskoleutdanning',
		'lo_about_stat2_number'  => '45–60',
		'lo_about_stat2_label'   => 'Min. per konsultasjon',
		'lo_about_stat3_number'  => '100%',
		'lo_about_stat3_label'   => 'Fokus på deg',

		// ── Osteopati ──────────────────────────────────────────────
		'lo_osteo_label'         => 'Osteopati',
		'lo_osteo_title'         => 'Hva er osteopati?',
		'lo_osteo_subtitle'      => 'En osteopat er autorisert helsepersonell med bred kunnskap om hvordan fysiske, psykiske og sosiale faktorer henger sammen og påvirker helsen din.',
		'lo_osteo_intro1'        => 'En osteopat skiller seg fra andre manuelle behandlere ved at osteopaten ser <strong>helheten</strong> i pasientens plager. Vi finner <strong>årsaken</strong> til symptomene — ikke bare behandler symptomene. Dette gjennomføres gjennom grundig undersøkelse og behandling som har som mål å finne funksjons- og bevegelsesforstyrrelser og å normalisere disse. Osteopaten behandler både akutte og kroniske lidelser.',
		'lo_osteo_intro2'        => 'Hos Lillestrøm Osteopati tilpasser vi behandlingen til dine behov. Vi kombinerer manuelle teknikker med veiledning og motivasjon — enten målet er å lindre akutte plager eller hjelpe deg til å mestre langvarige utfordringer.',
		'lo_osteo_card1_icon'    => 'fa-bone',
		'lo_osteo_card1_title'   => 'Parietal osteopati',
		'lo_osteo_card1_text'    => 'Behandling av muskel- og skjelettsystemet med teknikker som leddmobilisering, muskeltøyning, muskelenergiteknikker (MET) og manipulasjon.',
		'lo_osteo_card2_icon'    => 'fa-lungs',
		'lo_osteo_card2_title'   => 'Visceral osteopati',
		'lo_osteo_card2_text'    => 'Skånsomme teknikker rettet mot indre organer og deres bindevevssystem, for å stimulere økt bevegelse, sirkulasjon og nervefunksjon.',
		'lo_osteo_card3_icon'    => 'fa-brain',
		'lo_osteo_card3_title'   => 'Kranial osteopati',
		'lo_osteo_card3_text'    => 'Svært forsiktige teknikker rettet mot hodet, ryggmargen og nervesystemet — basert på de subtile bevegelsene mellom skallens knokler.',
		'lo_osteo_who_title'     => 'Hvem passer osteopati for?',
		'lo_osteo_who_text1'     => 'Osteopati passer for deg som ønsker en helhetlig tilnærming til helse og velvære. Vi behandler pasienter i alle aldre med smerter, skader eller sykdom i muskler og skjelett. Behandlingen tar utgangspunkt i sammenhengen mellom hverdagen, kroppen og plagene, og målet er å styrke pasientens evne til å hjelpe seg selv.',
		'lo_osteo_who_text2'     => 'Vi behandler et bredt spekter av muskel- og leddsmerter — fra idrettsskader og belastningsskader til kroniske plager. Behandlingen kan både lindre akutte smerter og bidra til å forebygge fremtidige skader.',

		// ── Behandlinger ───────────────────────────────────────────
		'lo_behandlinger_label'    => 'Behandlinger',
		'lo_behandlinger_title'    => 'Hva kan vi hjelpe deg med?',
		'lo_behandlinger_subtitle' => 'Osteopati kan hjelpe med et bredt spekter av plager. Her er noen av de vanligste tilstandene vi behandler.',

		// ── Prosess ────────────────────────────────────────────────
		'lo_prosess_label'        => 'Slik jobber vi',
		'lo_prosess_title'        => 'Din første konsultasjon',
		'lo_prosess_step1_title'  => 'Samtale',
		'lo_prosess_step1_text'   => 'Vi starter med en grundig samtale om dine plager, sykehistorie og hva du ønsker hjelp med.',
		'lo_prosess_step2_title'  => 'Undersøkelse',
		'lo_prosess_step2_text'   => 'En klinisk undersøkelse for å kartlegge bevegelse, smerte og funksjon i de aktuelle områdene.',
		'lo_prosess_step3_title'  => 'Behandling',
		'lo_prosess_step3_text'   => 'Skånsomme, manuelle teknikker tilpasset dine behov — med kroppen som helhet i fokus.',
		'lo_prosess_step4_title'  => 'Oppfølging',
		'lo_prosess_step4_text'   => 'Du får øvelser og råd med hjem, og vi legger en plan for videre behandling ved behov.',

		// ── Behandlere ─────────────────────────────────────────────
		'lo_behandlere_label'              => 'Behandlere',
		'lo_behandlere_title'              => 'Møt våre behandlere',
		'lo_behandlere_education_heading'  => 'Utdanning',
		'lo_behandlere_interests_heading'  => 'Faglige interesseområder',

		// ── Forsikring ─────────────────────────────────────────────
		'lo_forsikring_label'              => 'Forsikring',
		'lo_forsikring_title'              => 'Behandlingsforsikring',
		'lo_forsikring_subtitle'           => 'Dersom du har helseforsikring privat eller via arbeidsgiver, kan det være at forsikringsselskapet dekker utgiftene til behandling. Undersøk med din arbeidsgiver og ditt forsikringsselskap. Vi kan i mange tilfeller fakturere direkte.',
		'lo_forsikring_steps_heading'      => 'Slik bruker du forsikringen din',
		'lo_forsikring_step1_title'        => 'Kontakt forsikringsselskapet',
		'lo_forsikring_step1_text'         => 'Ring forsikringsselskapet ditt og meld inn sak. Du får et saksnummer.',
		'lo_forsikring_step2_title'        => 'Bestill time hos oss',
		'lo_forsikring_step2_text'         => 'Oppgi saksnummeret når du bestiller time, så ordner vi resten.',
		'lo_forsikring_step3_title'        => 'Vi fakturerer direkte',
		'lo_forsikring_step3_text'         => 'I de fleste tilfeller kan vi sende regningen rett til forsikringsselskapet.',
		'lo_forsikring_companies_heading'  => 'Vi samarbeider med blant annet',
		'lo_forsikring_companies'          => 'If / Vertikal Helse, Storebrand, Gjensidige, Tryg, DNB, SpareBank 1',
		'lo_forsikring_note'               => 'Har du et annet forsikringsselskap? Ta kontakt — vi hjelper deg gjerne med å finne ut om din forsikring dekker behandlingen.',

		// ── Bedrift ────────────────────────────────────────────────
		'lo_bedrift_label'          => 'Bedrift',
		'lo_bedrift_title'          => 'Osteopati for bedrifter',
		'lo_bedrift_subtitle'       => 'Vi ønsker å tilrettelegge for å bedre helsen til de ansatte — gjennom grundig undersøkelse, behandling og forebyggende tiltak tilpasset hver enkelt.',
		'lo_bedrift_benefit1_text'  => 'Redusert sykefravær',
		'lo_bedrift_benefit1_icon'  => 'fa-calendar-check',
		'lo_bedrift_benefit2_text'  => 'Økt trivsel',
		'lo_bedrift_benefit2_icon'  => 'fa-smile',
		'lo_bedrift_benefit3_text'  => 'Reduserte kostnader',
		'lo_bedrift_benefit3_icon'  => 'fa-piggy-bank',
		'lo_bedrift_benefit4_text'  => 'Økt yteevne og effektivitet',
		'lo_bedrift_benefit4_icon'  => 'fa-chart-line',
		'lo_bedrift_benefit5_text'  => 'Godt arbeidsmiljø',
		'lo_bedrift_benefit5_icon'  => 'fa-users',
		'lo_bedrift_description'    => 'Gjennom tester, samtaler og kartlegging av bedriften kommer vi fram til en hensiktsmessig og kostnadseffektiv løsning. Vi kan forhindre at ansatte med plager forsvinner ut i sykemelding, forebygge overbelastning og skader hos friske arbeidstakere, og hjelpe allerede sykemeldte tilbake i arbeid.',
		'lo_bedrift_card1_icon'     => 'fa-building',
		'lo_bedrift_card1_title'    => 'Behandling på arbeidsplassen',
		'lo_bedrift_card1_text'     => 'Vi kommer til bedriften med faste intervaller og behandler de ansatte på arbeidsplassen. Vi har med eget utstyr og trenger kun et rom.',
		'lo_bedrift_card2_icon'     => 'fa-receipt',
		'lo_bedrift_card2_title'    => 'Fleksibel betaling',
		'lo_bedrift_card2_text'     => 'Bedriften dekker deler eller hele behandlingssummen. Vi sender faktura ved månedsslutt, eller etter avtale. Eventuell egenandel kan trekkes av lønnen.',
		'lo_bedrift_card3_icon'     => 'fa-percentage',
		'lo_bedrift_card3_title'    => 'Skattefradrag',
		'lo_bedrift_card3_text'     => 'Forebyggende behandling som foregår hos bedriften gir skattefradrag. Den ansatte skal ikke belastes med fordelsbeskatning.',
		'lo_bedrift_stat_icon'      => 'fa-exclamation-triangle',
		'lo_bedrift_stat_heading'   => 'Sykefravær er en stor utgift',
		'lo_bedrift_stat1'          => 'Muskel- og skjelettlidelser er den vanligste årsaken til lengre sykefravær.',
		'lo_bedrift_stat2'          => 'SINTEF har regnet ut at bedriften taper i gjennomsnitt 13.000 kroner per uke ved sykefravær av en ansatt. Lønnsutgifter kommer i tillegg.',
		'lo_bedrift_stat3'          => 'Statistikk fra NAV viser over 10,4 millioner sykefraværsdager som følge av muskel- og skjelettlidelser — tilsvarende over 2 millioner ukeverk.',
		'lo_bedrift_cta_text'       => 'Kontakt Lillestrøm Osteopati Bedrift for tilbud. Vi kommer gjerne ut til bedriften for en presentasjon om hva vi kan tilby.',
		'lo_bedrift_cta_button'     => 'Kontakt oss for tilbud',

		// ── Priser ─────────────────────────────────────────────────
		'lo_priser_label'       => 'Priser',
		'lo_priser_title'       => 'Våre priser',
		'lo_priser_badge'       => 'Vanligst',
		'lo_price1_title'       => 'Ny pasient / Førstekonsultasjon',
		'lo_price1_desc'        => 'Inkluderer samtale, undersøkelse og behandling (ca. 60 min)',
		'lo_price1_amount'      => 'Pris kommer',
		'lo_price2_title'       => 'Oppfølgende behandling',
		'lo_price2_desc'        => 'Behandling for eksisterende pasienter (ca. 45 min)',
		'lo_price2_amount'      => 'Pris kommer',
		'lo_price3_title'       => 'Barn (under 16 år)',
		'lo_price3_desc'        => 'Tilpasset konsultasjon og behandling for barn',
		'lo_price3_amount'      => 'Pris kommer',
		'lo_priser_helfo_note'  => 'Osteopati er ikke dekket av Helfo. Behandling betales privat eller via behandlingsforsikring.',
		'lo_priser_cancel_note' => 'Vi ber om at avbestilling skjer senest 24 timer før avtalt time.',

		// ── Kontakt ────────────────────────────────────────────────
		'lo_kontakt_label'        => 'Kontakt',
		'lo_kontakt_title'        => 'Finn oss i Lillestrøm',
		'lo_kontakt_form_heading' => 'Send oss en melding',
		'lo_contact_address'      => "Lillestrøm sentrum\nLillestrøm, Norge",
		'lo_contact_phone'        => '+47 99 100 111',
		'lo_contact_email'        => 'post@lillestrom-osteopati.no',
		'lo_contact_hours'        => "Mandag – Fredag: 08:00 – 18:00\nLørdag: Etter avtale\nSøndag: Stengt",

		// ── CTA (Timebestilling) ───────────────────────────────────
		'lo_cta_title'       => 'Klar for å ta vare på kroppen din?',
		'lo_cta_text'        => 'Bestill time i dag — ingen henvisning nødvendig. Vi tar oss tid til å finne de underliggende årsakene til plagene dine.',
		'lo_cta_phone'       => '99 100 111',
		'lo_cta_btn_call'    => 'Ring',
		'lo_cta_btn_email'   => 'Send e-post',
		'lo_cta_trust_note'  => 'Autorisert helsepersonell — underlagt Helsedirektoratets krav',
		'lo_cta_trust_icon'  => 'fa-shield-alt',

		// ── FAQ ────────────────────────────────────────────────────
		'lo_faq_label'  => 'Spørsmål og svar',
		'lo_faq_title'  => 'Ofte stilte spørsmål',

		// ── Footer ─────────────────────────────────────────────────
		'lo_footer_tagline'        => 'Profesjonell osteopatisk behandling i hjertet av Lillestrøm. Autorisert helsepersonell siden 2022.',
		'lo_footer_copyright'      => 'Lillestrøm Osteopati. Alle rettigheter reservert.',
		'lo_footer_membership'     => 'Norsk Osteopatforbund',
		'lo_footer_membership_url' => 'https://osteopati.org',

		// ── Takk (Thank You) ───────────────────────────────────────
		'lo_takk_heading' => 'Takk for din henvendelse!',
		'lo_takk_text'    => 'Vi har mottatt meldingen din og vil svare deg så snart som mulig — vanligvis innen en virkedag.',
		'lo_takk_button'  => 'Tilbake til forsiden',
	);

	foreach ( $defaults as $key => $value ) {
		// Only set if the mod has never been saved (returns false).
		if ( false === get_theme_mod( $key ) ) {
			set_theme_mod( $key, $value );
		}
	}
}


/* --------------------------------------------------------------------------
 * 1. Static Front Page
 * ----------------------------------------------------------------------- */

/**
 * Create the "Hjem" page (if it doesn't exist) and configure it as the
 * static front page in WordPress reading settings.
 *
 * @return void
 */
function lo_setup_front_page() {

	// Check if a page with the slug "hjem" already exists.
	$existing = get_posts( array(
		'post_type'      => 'page',
		'name'           => 'hjem',
		'post_status'    => 'any',
		'posts_per_page' => 1,
		'fields'         => 'ids',
	) );

	if ( ! empty( $existing ) ) {
		$page_id = $existing[0];
	} else {
		$page_id = wp_insert_post( array(
			'post_type'   => 'page',
			'post_title'  => 'Hjem',
			'post_name'   => 'hjem',
			'post_status' => 'publish',
		) );

		if ( is_wp_error( $page_id ) ) {
			return;
		}
	}

	// Set this page as the static front page.
	update_option( 'show_on_front', 'page' );
	update_option( 'page_on_front', $page_id );
}


/* --------------------------------------------------------------------------
 * 2. Primary Navigation Menu
 * ----------------------------------------------------------------------- */

/**
 * Create the "Hovedmeny" nav menu with anchor-link items and assign it
 * to the "primary" theme location.
 *
 * @return void
 */
function lo_setup_primary_menu() {

	$menu_name = 'Hovedmeny';

	// Check if the menu already exists.
	$menu_exists = wp_get_nav_menu_object( $menu_name );

	if ( $menu_exists ) {
		$menu_id = $menu_exists->term_id;
	} else {
		$menu_id = wp_create_nav_menu( $menu_name );

		if ( is_wp_error( $menu_id ) ) {
			return;
		}

		// Define menu items: label => fragment identifier.
		$menu_items = array(
			'Hjem'         => '#hjem',
			'Om oss'       => '#om-oss',
			'Osteopati'    => '#osteopati',
			'Behandlinger' => '#behandlinger',
			'Behandlere'   => '#behandlere',
			'Forsikring'   => '#forsikring',
			'Bedrift'      => '#bedrift',
			'Priser'       => '#priser',
			'FAQ'          => '#faq',
			'Kontakt'      => '#kontakt',
			'Bestill time' => '#timebestilling',
		);

		$position = 1;
		foreach ( $menu_items as $title => $fragment ) {
			wp_update_nav_menu_item( $menu_id, 0, array(
				'menu-item-title'   => $title,
				'menu-item-url'     => home_url( '/' ) . $fragment,
				'menu-item-status'  => 'publish',
				'menu-item-type'    => 'custom',
				'menu-item-position' => $position,
			) );
			$position++;
		}
	}

	// Assign the menu to the "primary" theme location.
	$locations            = get_theme_mod( 'nav_menu_locations', array() );
	$locations['primary'] = $menu_id;
	set_theme_mod( 'nav_menu_locations', $locations );
}


/* --------------------------------------------------------------------------
 * 3. Behandler (Staff) Posts
 * ----------------------------------------------------------------------- */

/**
 * Create the initial Behandler (practitioner) post for Thomas Sewell,
 * including custom meta fields, if no behandler posts exist yet.
 *
 * @return void
 */
function lo_setup_behandler_posts() {

	// Only create if no behandler posts exist.
	$existing = get_posts( array(
		'post_type'      => 'behandler',
		'post_status'    => 'any',
		'posts_per_page' => 1,
		'fields'         => 'ids',
	) );

	if ( ! empty( $existing ) ) {
		return;
	}

	$bio  = 'Thomas Sewell er autorisert fysioterapeut og osteopat D.O. MNOF, med lang klinisk erfaring innen utredning og behandling av muskel- og skjelettplager. Han jobber helhetlig med kroppen, med særlig interesse for sammenhengen mellom nakke, nervesystem og hodepineproblematikk.' . "\n\n";
	$bio .= 'Thomas har spesialkompetanse innen behandling av migrene og cervikogen hodepine, samt komplekse og sammensatte smertebilder i nakke, rygg og skulder. Han kombinerer osteopati, fysioterapi og kognitiv forståelse i møte med pasienten, med mål om varig bedring og økt funksjon i hverdagen.';

	$post_id = wp_insert_post( array(
		'post_type'    => 'behandler',
		'post_title'   => 'Thomas Sewell',
		'post_content' => $bio,
		'post_status'  => 'publish',
	) );

	if ( is_wp_error( $post_id ) ) {
		return;
	}

	// Professional title.
	update_post_meta( $post_id, '_behandler_title', 'Osteopat D.O. MNOF & Fysioterapeut' );

	// Education (one entry per line).
	$education  = "Osteopat D.O. MNOF — Nordisk Akademi for Osteopati\n";
	$education .= "Klinisk eksamen ved European School of Osteopathy (ESO), Maidstone, Kent, England (2002)\n";
	$education .= "Klassisk osteopati — The John Wernham College of Classical Osteopathy (2006–2008)\n";
	$education .= "Fysioterapeut — HAN University of Applied Sciences, Arnhem og Nijmegen, Nederland (1996)\n";
	$education .= 'Videreutdanning i kognitiv terapi for helsepersonell';
	update_post_meta( $post_id, '_behandler_education', $education );

	// Specialties (one entry per line).
	$specialties  = "Muskel- og skjelettplager i sin helhet\n";
	$specialties .= "Migrene og cervikogen hodepine\n";
	$specialties .= "Nakke- og skulderproblematikk\n";
	$specialties .= "Sammenheng mellom smerte, stress og nervesystem\n";
	$specialties .= 'Helhetlig vurdering og individuelt tilpasset behandling';
	update_post_meta( $post_id, '_behandler_specialties', $specialties );
}


/* --------------------------------------------------------------------------
 * 4. FAQ Posts
 * ----------------------------------------------------------------------- */

/**
 * Create the initial set of FAQ posts (faq_item CPT) if none exist yet.
 * Each FAQ uses the post title for the question and post content for the answer.
 * menu_order controls display ordering.
 *
 * @return void
 */
function lo_setup_faq_posts() {

	// Only create if no FAQ posts exist.
	$existing = get_posts( array(
		'post_type'      => 'faq_item',
		'post_status'    => 'any',
		'posts_per_page' => 1,
		'fields'         => 'ids',
	) );

	if ( ! empty( $existing ) ) {
		return;
	}

	$faqs = array(
		array(
			'title' => 'Hvem passer osteopati for?',
			'answer' => 'Osteopati passer for deg som ønsker en helhetlig tilnærming til helse og velvære. Vi behandler pasienter i alle aldre med smerter, skader eller sykdom i muskler og skjelett — fra idrettsskader og belastningsskader til kroniske plager. Behandlingen kan både lindre akutte smerter og bidra til å forebygge fremtidige skader. Visste du at behandling hos osteopat dekkes av de fleste helseforsikringer?',
			'order' => 1,
		),
		array(
			'title' => 'Hvilken utdanning har en osteopat?',
			'answer' => 'Osteopater er autoriserte helsepersonell og medlemmer av Norsk Osteopatforbund. Utdanningen til osteopat er fireårig, med en treårig bachelor og ett års videreutdanning. I Norge er Høyskolen Kristiania den eneste skolen som tilbyr dette studiet. Flere av våre behandlere har også utdanning fra den anerkjente ESO — European School of Osteopathy i Kent, England.',
			'order' => 2,
		),
		array(
			'title' => 'Kan en osteopat henvise videre?',
			'answer' => 'Ved behov kan osteopaten henvise deg til fastlegen med en beskrivelse. Henvisning til spesialist eller bildediagnostikk er mulig privat, altså uten Helfo-finansiering. For offentlige henvisninger til spesialist eller bildediagnostikk må du gå via fastlege, manuellterapeut eller kiropraktor.',
			'order' => 3,
		),
		array(
			'title' => 'Kan en osteopat sykmelde?',
			'answer' => 'Nei, osteopater kan ikke sykmelde. Vi samarbeider likevel tett med fastleger og kommuniserer via Norsk Helsenett. Ved mistanke om annen sykdom kan vi be din fastlege om å henvise til bildediagnostikk som MR eller røntgen.',
			'order' => 4,
		),
		array(
			'title' => 'Trenger jeg henvisning fra lege?',
			'answer' => 'Nei, du trenger ingen henvisning. Osteopater er primærkontakter i førstelinjetjenesten, og du kan bestille time direkte hos oss.',
			'order' => 5,
		),
		array(
			'title' => 'Dekkes behandlingen av forsikring?',
			'answer' => 'Dersom du har helseforsikring privat eller via arbeidsgiver, kan det være at forsikringsselskapet dekker utgiftene til behandling. Undersøk med din arbeidsgiver og ditt forsikringsselskap. Osteopati er ikke dekket av Helfo — behandling betales privat eller via behandlingsforsikring. Vi kan i mange tilfeller fakturere forsikringsselskapet direkte.',
			'order' => 6,
		),
		array(
			'title' => 'Hva skjer på første konsultasjon?',
			'answer' => 'Undersøkelsen leder til en osteopatisk diagnose som viser oss hvor i kroppen de viktigste dysfunksjonene er. Denne diagnosen avgjør behandlingen, som består av manuelle teknikker — mobilisering, leddmanipulasjon, avspenning, triggerpunktbehandling og muskeltøyninger. Behandlingen har en trygg og skånsom tilnærming, og hver pasient får spesielt tilrettelagt behandling ut fra sine plager.',
			'order' => 7,
		),
		array(
			'title' => 'Hva er avbestillingsfristen?',
			'answer' => 'Vi ber om at avbestilling skjer senest 24 timer før avtalt time.',
			'order' => 8,
		),
	);

	foreach ( $faqs as $faq ) {
		wp_insert_post( array(
			'post_type'    => 'faq_item',
			'post_title'   => $faq['title'],
			'post_content' => $faq['answer'],
			'post_status'  => 'publish',
			'menu_order'   => $faq['order'],
		) );
	}
}


/* --------------------------------------------------------------------------
 * 5. Behandling (Treatment) Cards
 * ----------------------------------------------------------------------- */

function lo_setup_behandling_posts() {
	$existing = get_posts( array( 'post_type' => 'behandling_type', 'post_status' => 'any', 'posts_per_page' => 1, 'fields' => 'ids' ) );
	if ( ! empty( $existing ) ) {
		return;
	}

	$treatments = array(
		array( 'title' => 'Rygg- og nakkesmerter',      'desc' => 'Akutte og langvarige smerter i rygg, nakke og korsrygg. Prolaps, isjias og stivhet.',                          'icon' => 'fa-arrow-down' ),
		array( 'title' => 'Hodepine og migrene',         'desc' => 'Spenningshodepine, migrene og nakkerelatert hodepine som kan lindres med manuelle teknikker.',                   'icon' => 'fa-head-side-virus' ),
		array( 'title' => 'Idrettsskader',               'desc' => 'Forstrekninger, senebetennelser, overbelastningsskader og rehabilitering etter skade.',                         'icon' => 'fa-running' ),
		array( 'title' => 'Barn og spedbarn',             'desc' => 'Skånsomme teknikker for kolikk, urolige barn, skjevheter og ammeproblemer.',                                   'icon' => 'fa-baby' ),
		array( 'title' => 'Graviditet',                   'desc' => 'Bekkensmerter, ryggsmerter og andre plager knyttet til svangerskap og fødsel.',                                 'icon' => 'fa-female' ),
		array( 'title' => 'Skulder, albue og hånd',      'desc' => 'Frozen shoulder, tennisalbue, karpaltunnelsyndrom og andre plager i overekstremitetene.',                       'icon' => 'fa-hand-paper' ),
		array( 'title' => 'Kne, hofte og fot',           'desc' => 'Artrose, løperkne, hælspore, plantarfasciitt og andre plager i underekstremitetene.',                          'icon' => 'fa-shoe-prints' ),
		array( 'title' => 'Stivhet og nedsatt funksjon', 'desc' => 'Generelt nedsatt bevegelighet, muskelstramhet og funksjonelle plager i hverdagen.',                             'icon' => 'fa-couch' ),
		array( 'title' => 'Mage- og fordøyelsesplager',  'desc' => 'Funksjonelle mage-, tarm- og urinveisplager, sure oppstøt, halsbrann og fordøyelsesbesvær.',                  'icon' => 'fa-stomach' ),
		array( 'title' => 'Pustebesvær',                  'desc' => 'Tung pust og nedsatt pustefunksjon knyttet til stramhet i brystkasse og mellomgulv.',                          'icon' => 'fa-wind' ),
		array( 'title' => 'Kontorplager',                 'desc' => 'Belastningsskader og plager fra stillesittende arbeid, dårlig ergonomi og ensidig belastning.',                'icon' => 'fa-laptop' ),
		array( 'title' => 'Seneskjedebetennelser',        'desc' => 'Betennelser i seneskjeder, overbelastningsskader og repetitive belastningsplager.',                            'icon' => 'fa-hand-sparkles' ),
	);

	$order = 1;
	foreach ( $treatments as $t ) {
		$post_id = wp_insert_post( array(
			'post_type'    => 'behandling_type',
			'post_title'   => $t['title'],
			'post_content' => $t['desc'],
			'post_status'  => 'publish',
			'menu_order'   => $order,
		) );
		if ( ! is_wp_error( $post_id ) ) {
			update_post_meta( $post_id, '_behandling_icon', $t['icon'] );
		}
		$order++;
	}
}


/* --------------------------------------------------------------------------
 * 6. Contact Form 7 Form
 * ----------------------------------------------------------------------- */

/**
 * Create a Contact Form 7 form for the site if CF7 is active and no forms
 * exist yet. Stores the form ID as a theme mod for easy retrieval.
 *
 * @return void
 */
function lo_setup_cf7_form() {

	// Check if Contact Form 7 class is available (plugin must be active).
	if ( ! class_exists( 'WPCF7_ContactForm' ) ) {
		return;
	}

	// Check if a CF7 form already exists.
	$existing_forms = get_posts( array(
		'post_type'      => 'wpcf7_contact_form',
		'post_status'    => 'any',
		'posts_per_page' => 1,
		'fields'         => 'ids',
	) );

	if ( ! empty( $existing_forms ) ) {
		return;
	}

	// Build the form markup.
	$form_template = '<div class="form-group">
<label>Navn <span class="required">*</span></label>
[text* your-name placeholder "Ditt fulle navn"]
</div>

<div class="form-group">
<label>E-post <span class="required">*</span></label>
[email* your-email placeholder "din@epost.no"]
</div>

<div class="form-group">
<label>Telefon</label>
[tel your-phone placeholder "Valgfritt"]
</div>

<div class="form-group">
<label>Melding <span class="required">*</span></label>
[textarea* your-message placeholder "Beskriv kort hva du ønsker hjelp med..."]
</div>

[submit class:btn class:btn-primary class:btn-submit "Send melding"]';

	// Mail template.
	$mail_body  = "Navn: [your-name]\n";
	$mail_body .= "E-post: [your-email]\n";
	$mail_body .= "Telefon: [your-phone]\n\n";
	$mail_body .= "Melding:\n[your-message]";

	// Create the form using the CF7 API — wrapped in try/catch for safety.
	try {
		if ( ! method_exists( 'WPCF7_ContactForm', 'get_template' ) ) {
			return;
		}

		$contact_form = WPCF7_ContactForm::get_template();

		if ( ! $contact_form || ! is_object( $contact_form ) ) {
			return;
		}

		$contact_form->set_title( 'Kontaktskjema' );

		$contact_form->set_properties( array(
			'form'             => $form_template,
			'mail'             => array(
				'active'             => true,
				'subject'            => 'Ny henvendelse fra nettsiden — [your-name]',
				'sender'             => '[your-name] <[your-email]>',
				'recipient'          => 'post@lillestrom-osteopati.no',
				'body'               => $mail_body,
				'additional_headers' => 'Reply-To: [your-email]',
				'attachments'        => '',
				'use_html'           => false,
			),
			'mail_2'           => array(
				'active' => false,
			),
			'messages'         => array(),
			'additional_settings' => '',
		) );

		$form_id = $contact_form->save();

		if ( $form_id ) {
			// Store the form ID as a theme mod for easy access in templates.
			set_theme_mod( 'lo_cf7_form_id', $form_id );
		}
	} catch ( Exception $e ) {
		// Silently fail — CF7 form can be created manually later.
		return;
	}
}
