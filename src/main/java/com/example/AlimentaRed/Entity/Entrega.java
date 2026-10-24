package com.example.AlimentaRed.Entity;

import com.example.AlimentaRed.Entity.Enum.EstadoEntrega;
import jakarta.persistence.*;
import lombok.Data;

@Data
@Entity
@Table(name = "entrega")

public class Entrega {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long idEntrega;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private EstadoEntrega estado;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "solicitud_id")
    private Solicitud solicitud;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "asignacion_id")
    private Asignacion asignacion;

    @Column(nullable = false)
    private int cantidadAsignada;
}
