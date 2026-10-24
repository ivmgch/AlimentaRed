package com.example.AlimentaRed.Entity;

import jakarta.persistence.*;
import lombok.Data;

@Data
@Entity
@Table(name = "strike")

public class Strike {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long idStrike;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "organizacion_id")
    private Organizacion organizacion;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "asignacion_id")
    private Asignacion asignacion;

    @Column(nullable = false)
    private String nombreStrike;

    @Column(length = 500)
    private String detalles;
}
